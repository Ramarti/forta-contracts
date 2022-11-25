/*
const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');
const { prepare } = require('./fixture');
const scannerData = require('../scripts/data/scanners/matic/scanners.json');
const { subjectToActive } = require('../scripts/utils/staking.js');
const { migrateFirstScanner, migratePool, scanner2ScannerPool } = require('../scripts/scanner-migration/migrate-scanners');

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

describe('Scanner 2 Scanner pool script', function () {
    prepare();
    beforeEach(async function () {
        this.accounts.getAccount('scanner');
        const ScannerRegistry_0_1_3 = await ethers.getContractFactory('ScannerRegistry_0_1_3');
        this.scanners = await upgrades.deployProxy(ScannerRegistry_0_1_3, [this.contracts.access.address, 'Forta Scanners', 'FScanners'], {
            kind: 'uups',
            constructorArgs: [this.contracts.forwarder.address],
            unsafeAllow: ['delegatecall'],
        });
        await this.scanners.deployed();
        await this.subjectGateway.connect(this.accounts.admin).setStakeSubject(0, this.scanners.address);
        await this.token.connect(this.accounts.minter).mint(this.accounts.user1.address, ethers.utils.parseEther('100000000'));
        await this.token.connect(this.accounts.user1).approve(this.staking.address, ethers.constants.MaxUint256);
    });
    describe('Operations', function () {
        it.only('migrates first pool and updates doc', async function () {
            const mfs = new MockFs();
            await this.scanners.connect(this.account.manager).adminRegister(this.accounts.scanner.address, this.account.user1.address, 1, 'data');
            await migrateFirstScanner(mfs, this.scanners, this.accounts.scanner.address, this.account.user1.address, 1);
            expect(mfs.path).to.eq('./scripts/data/scanners/unknown/migration-scanners.json');
            expect(mfs.dataString).to.eq(JSON.stringify());
        });
    });
    describe('Full test', function () {
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
                constructorArgs: [this.contracts.forwarder.address],
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
*/