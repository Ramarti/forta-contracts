const { ethers } = require('hardhat');
const utils = require('./utils');
const deployEnv = require('./loadEnv');
const { signERC712ScannerRegistration } = require('./utils/scannerRegistration');
const { BigNumber } = require('ethers');

async function main(config = {}) {
    const e = await deployEnv.loadEnv();
    const signer = (await ethers.getSigners())[0];
    const balance = await e.contracts.scannerPools.balanceOf(signer.address);
    /*
    if (balance.eq(BigNumber.from(0))) {
        await e.contracts.scannerPools.registerScannerPool(137);
    }

    const stake = await e.contracts.staking.activeStakeFor(2, 2);
    let tx;
    if (stake.eq(BigNumber.from(0))) {
        tx = await e.contracts.token.approve(e.contracts.staking.address, ethers.constants.MaxUint256);
        await tx.wait();
        console.log(tx);

        tx = await e.contracts.staking.deposit(2, 2, ethers.utils.parseEther('1000'));
        console.log(await tx.wait());
    }
    */

    const verifyingContractInfo = {
        address: e.contracts.scannerPools.address,
        chainId: e.network.chainId,
    };

    const scanner1Registration = {
        scanner: signer.address,
        scannerPoolId: 2,
        chainId: 137,
        metadata: '',
        timestamp: (await ethers.provider.getBlock('latest')).timestamp,
    };
    console.log(signer.address);
    const signature = await signERC712ScannerRegistration(verifyingContractInfo, scanner1Registration, signer);
    console.log(verifyingContractInfo);
    console.log(scanner1Registration);
    
    console.log('signature');
    console.log(signature);

    let tx = await e.contracts.scannerPools.registerScannerNode(scanner1Registration, signature);
    console.log(tx);
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

module.exports = main;
