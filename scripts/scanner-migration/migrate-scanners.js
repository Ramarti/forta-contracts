const { ethers } = require('hardhat');
const utils = require('./utils');
const deployEnv = require('./loadEnv');
const fs = require('fs');
const scannerData = require('./data/scanners/matic/scanners.json');

function updateScannerData(newData, network) {
    fs.writeFileSync(`./scripts/data/scanners/${network.name}/migration-scanners.json`, JSON.stringify(newData), null, 2);
}

const CHUNK_SIZE = 100;

async function migratePool(scanners, chunkSize, contracts, poolId) {
    /*if (poolId === 0)
    const chunks = scanners.chunk(chunkSize);
    for (const chunk of chunks) {
        const calls = chunk.map((s) => contracts.registryMigration.interface.encodeFunctionData('migrate', [
            s.id,
            poolId,
            s.owner,
            s.chainId
        ]));
        const tx = await contracts.scanners.multicall(calls);
        const receipt = await tx.wait();
        
    }*/
}

async function migrateFirstScanner(fs, scanners, scannerAddress, owner, chainId) {
    const tx = await scanners.registryMigration.migrate(
        scannerAddress,
        0,
        owner,
        chainId
    );
    const receipt = await tx.wait();
    console.log(receipt.logs);
}

async function scanner2ScannerPool(config = {}) {
    let e;
    if (!config.deployer || !config.contracts || !config.network) {
        e = await deployEnv.loadEnv();
    }
    const deployer = config.deployer ?? e.deployer;
    const contracts = config.contracts ?? e.contracts;
    const network = config.network ?? e.network;
    const chunkSize = config.chunkSize ?? CHUNK_SIZE;
    updateScannerData(scannerData, network);
    console.log(`Deployer: ${deployer.address}`);
    console.log('--------------------- Scanner 2 ScannerPool -------------------------------');
    const chains = Object.keys(scannerData);
    for (const chain of chains) {
        console.log('Chain ', chain);
        const owners = Object.keys(scannerData[chains]);
        for (const owner of owners) {
            console.log('Owner ', owner);
            const scanners = owners[owner].scanner.filter(s => !s.migrated);
            let poolId = owners[owner].poolId;
            const migrations = migratePool(scanners, chunkSize, contracts)
        }
    }
}

if (require.main === module) {
    scanner2ScannerPool()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

module.exports.scanner2ScannerPool = scanner2ScannerPool;
module.exports.migrateFirstScanner = migrateFirstScanner;

