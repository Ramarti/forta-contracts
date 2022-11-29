const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');
const { prepare } = require('./fixture');
const scannerData = require('../../scripts/data/scanners/matic/scanners.json');
const { utils } = require('../../scripts/utils');
const { subjectToActive } = require('../../scripts/utils/staking.js');
const { migrateFirstScanner, migratePool, scanner2ScannerPool } = require('../../scripts/scanner-migration/migrate-scanners');

class MockFs {
    constructor() {
        this.path = '';
        this.dataString = '';
    }
    writeFileSync(path, dataString) {
        this.path = path;
        this.dataString = dataString;
    }
}

const MIN_STAKE_MANAGED = '100';
const MAX_STAKE_MANAGED = '100000';

async function upgrade(that) {
    const ScannerRegistry = await ethers.getContractFactory('ScannerRegistry');
    that.scanners = await upgrades.upgradeProxy(that.scanners.address, ScannerRegistry, {
        constructorArgs: [this.contracts.forwarder.address],
        unsafeAllow: ['delegatecall'],
        unsafeSkipStorageCheck: true,
    });

    await that.scanners.connect.setSubjectHandler(that.subjectGateway.address);

    const FortaStaking = await ethers.getContractFactory('FortaStaking');
    that.staking = await upgrades.upgradeProxy(that.staking.address, FortaStaking, {
        constructorArgs: [that.that.forwarder.address],
        unsafeAllow: ['delegatecall'],
    });
    await that.staking.configureStakeHelpers(that.subjectGateway.address, that.stakeAllocator.address, that.rewardsDistributor.address);

    await that.scanners.configureMigration(10000 + (await ethers.provider.getBlock('latest')).timestamp, that.scannerPools.address);

    // Increase time to after migration
    await ethers.provider.send('evm_setNextBlockTimestamp', [(await that.scanners.sunsettingTime()).toNumber() + 1]);
    await ethers.provider.send('evm_mine');
}

let scannerAddress;
describe('Scanner 2 Scanner pool script', function () {
    prepare({
        stake: {
            scanners: { min: MIN_STAKE_MANAGED, max: MAX_STAKE_MANAGED, activated: true },
        },
    });
    beforeEach(async function () {
        scannerAddress = this.accounts.other.address;

        await this.scanners.deployed();
        await this.subjectGateway.connect(this.accounts.admin).setStakeSubject(0, scannerAddress);
        await this.token.connect(this.accounts.minter).mint(this.accounts.user1.address, ethers.utils.parseEther('100000000'));
        await this.token.connect(this.accounts.user1).approve(this.staking.address, ethers.constants.MaxUint256);
    });
    describe('Operations', function () {
        it.only('migrates first pool and updates doc', async function () {
            const mfs = new MockFs();
            await this.scanners.connect(this.accounts.manager).adminRegister(scannerAddress, this.accounts.user1.address, 137, 'data');
            await this.staking.connect(this.accounts.user1).deposit(0, scannerAddress, MIN_STAKE_MANAGED);
            upgrade(this);
            await migrateFirstScanner(mfs, this.scanners, scannerAddress, this.accounts.user1.address, 137);
            expect(mfs.path).to.eq('./scripts/data/scanners/unknown/migration-scanners.json');
            expect(mfs.dataString).to.eq(JSON.stringify());
            expect(await this.scanners.balanceOf(this.accounts.user1.address)).to.eq(0);
            expect(await this.scanners.isRegistered(this.accounts.scanner.address)).to.eq(false);
            expect(await this.staking.activeStakeFor(0, this.accounts.scanner.address)).to.eq(MIN_STAKE_MANAGED);
            expect(await this.scannerPools.balanceOf(this.accounts.user1.address)).to.eq(1);
            expect(await this.scannerPools.getScannerState(this.accounts.scanner.address)).to.eq([true, this.accounts.user1.address, 137, 'data', true, false]);
            expect(await this.staking.activeStakeFor(0, this.accounts.scanner.address)).to.eq(MIN_STAKE_MANAGED);
        });
    });
    describe.skip('Full test', function () {
        beforeEach(async function () {
            const chains = Object.keys(scannerData);
            for (const chain of chains) {
                console.log('Chain', chain);
                await this.scanners.connect(this.accounts.manager).setStakeThreshold({ min: '100', max: '500', activated: true }, chain);
                await this.scannerPools.connect(this.accounts.manager).setManagedStakeThreshold({ min: '100', max: '500', activated: true }, chain);
                const owners = Object.keys(scannerData[chains]);
                for (const owner of owners) {
                    console.log('Owner', owner);
                    for (const scanner of owners[owner].scanners) {
                        console.log('Scanner', scanner.address);
                        await this.scanners.connect(this.accounts.manager).adminRegister(scanner.id, owner, scanner.chainId, '');
                        if (scanner.enabled) {
                            await this.scanners.connect(this.accounts.manager).disableScanner(scanner.id, 0);
                        } else {
                            await this.staking.connect(this.accounts.user1).deposit(0, scanner.address, '100');
                            await this.staking
                                .connect(this.accounts.user1)
                                .safeTransferFrom(this.accounts.user1, owner, subjectToActive(0, scanner.id), '100', ethers.constants.HashZero);
                        }
                    }
                }
            }

            const NewImplementation = await ethers.getContractFactory('ScannerRegistry');
            this.scanners = await upgrades.upgradeProxy(this.scanners.address, NewImplementation, {
                constructorArgs: [this.that.forwarder.address],
                unsafeAllow: ['delegatecall'],
            });
            const { timestamp } = await this.accounts.user1.provider.getBlock('latest');
            await this.scanners.connect(this.accounts.admin).configureMigration(timestamp + 5000, await this.scannerPools.address);

            const deployer = (await ethers.getSigners())[0];

            const ScannerToScannerPoolMigration = await ethers.getContractFactory('ScannerToScannerPoolMigration', deployer);
            this.registryMigration = await upgrades.deployProxy(ScannerToScannerPoolMigration, [this.access.address], {
                kind: 'uups',
                constructorArgs: [this.forwarder.address, this.scanners.address, this.scannerPools.address, this.staking.address],
                unsafeAllow: 'delegatecall',
            });

            this.access.connect(this.accounts.admin).grantRole(this.roles.SCANNER_2_SCANNER_POOL_MIGRATOR, this.registryMigration.address);
        });

        it('migrates', async function () {
            await scanner2ScannerPool({});
        });
    });
});
