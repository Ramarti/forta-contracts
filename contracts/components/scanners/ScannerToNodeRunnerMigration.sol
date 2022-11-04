// SPDX-License-Identifier: UNLICENSED
// See Forta Network License: https://github.com/forta-network/forta-contracts/blob/master/LICENSE.md

pragma solidity ^0.8.9;

import "../BaseComponentUpgradeable.sol";
import "./ScannerRegistry.sol";
import "../scanner_pools/ScannerPoolRegistry.sol";
import "../staking/IStakeMigrator.sol";

/**
 * Migration of ScannerRegistry to ScannerPoolRegistry
 */
contract ScannerToNodeRunnerMigration is BaseComponentUpgradeable {
    /** Contract version */
    string public constant version = "0.1.0";
    uint256 public constant NODE_RUNNER_NOT_MIGRATED = 0;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ScannerRegistry public immutable scannerNodeRegistry;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ScannerPoolRegistry public immutable scannerPoolRegistry;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakeMigrator public immutable stakeMigrator;
    /// chainId => nodeRunnerAddress => nodeRunnerId
    mapping(uint256 => mapping(address => uint256)) private _migratedNodeRunners;

    event MigrationExecuted(uint256 scannersMigrated, uint256 scannersIgnored, uint256 indexed nodeRunnerId, bool mintedNodeRunner);

    error NotOwnerOfNodeRunner(address pretender, uint256 nodeRunnerId);
    error WrongScannerChainId(uint256 expected, uint256 provided, address scanner);
    error WrongNodeRunnerChainId(uint256 expected, uint256 provided, uint256 nodeRunnerId);
    error NodeRunnerAlreadyMigrated(uint256 nodeRunnerId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _forwarder,
        address _scannerNodeRegistry,
        address _scannerPoolRegistry,
        address _stakeMigrator
    ) initializer ForwardedContext(_forwarder) {
        if (_scannerNodeRegistry == address(0)) revert ZeroAddress("_scannerNodeRegistry");
        if (_scannerPoolRegistry == address(0)) revert ZeroAddress("_scannerPoolRegistry");
        if (_stakeMigrator == address(0)) revert ZeroAddress("_stakeMigrator");

        scannerNodeRegistry = ScannerRegistry(_scannerNodeRegistry);
        scannerPoolRegistry = ScannerPoolRegistry(_scannerPoolRegistry);
        stakeMigrator = IStakeMigrator(_stakeMigrator);
    }

    /**
     * @notice Initializer method, access point to initialize inheritance tree.
     * @param __manager address of AccessManager.
     */
    function initialize(address __manager) public initializer {
        __BaseComponentUpgradeable_init(__manager);
    }

    /**
     * @notice Method to self migrate from the old ScannerRegistry NFTs to a single ScannerPoolRegistry NFT, per chain.
     * WARNING: ScannerNodeRegistry's manager addresses will not be migrated, please user ScannerPoolRegistry's methods to set them again.
     * @param scanners array of scanner addresses to be migrated.
     * All the scanners willing to migrate (optingOutOfMigration flags set to false) ScannerRegistry ERC721 identified by the uint256(address)
     * in the input array will be:
     * - Registered in ScannerPoolRegistry to the nodeRunnerId either indicated or generated, with the same chainId and metadata.
     * - Deleted in ScannerNodeRegistry. The ERC721 will be burned, disabled flags and managers deleted from storage.
     * Scanners with optingOutOfMigration flags == true will be ignored (opted out), and will stay in ScannerNodeRegistry.
     * At migration end, they will stop receiving work and rewards.
     * @param nodeRunnerId If set as 0, a new ScannerPoolRegistry ERC721 will be minted to nodeRunner (but it must not own any prior),
     * otherwise must be set as a valid ScannerPoolRegistry ERC721 id owned by nodeRunner.
     * @return ScannerPoolRegistry ERC721 id the scanners are migrated to.
     */
    function selfMigrate(
        address[] calldata scanners,
        uint256 nodeRunnerId,
        uint256 chainId
    ) external returns (uint256) {
        return _migrate(scanners, nodeRunnerId, _msgSender(), chainId);
    }

    /**
     * @notice Method to migrate from the old ScannerRegistry NFTs to a single ScannerPoolRegistry NFT, executed by an address with the role
     * MIGRATION_EXECUTOR_ROLE.
     * WARNING: ScannerNodeRegistry's manager addresses will not be migrated, please user ScannerPoolRegistry's methods to set them again.
     * @param scanners array of scanner addresses to be migrated.
     * All the scanners willing to migrate (optingOutOfMigration flags set to false) ScannerRegistry ERC721 identified by the uint256(address)
     * in the input array will be:
     * - Registered in ScannerPoolRegistry to the nodeRunnerId either indicated or generated, with the same chainId and metadata.
     * - Deleted in ScannerNodeRegistry. The ERC721 will be burned, disabled flags and managers deleted from storage.
     * Scanners with with optingOutOfMigration flags == true will be ignored (opted out), and will stay in ScannerNodeRegistry.
     * @param nodeRunnerId If set as 0, a new ScannerPoolRegistry ERC721 will be minted to nodeRunner (but it must not own any prior),
     * otherwise must be set as a valid ScannerPoolRegistry ERC721 id owned by nodeRunner.
     * @param nodeRunner address that owns the scanners and will own the ScannerPoolRegistry ERC721
     * @return ScannerPoolRegistry ERC721 id the scanners are migrated to.
     */
    function migrate(
        address[] calldata scanners,
        uint256 nodeRunnerId,
        address nodeRunner,
        uint256 chainId
    ) external onlyRole(MIGRATION_EXECUTOR_ROLE) returns (uint256) {
        return _migrate(scanners, nodeRunnerId, nodeRunner, chainId);
    }

    function _migrate(
        address[] calldata scanners,
        uint256 inputNodeRunnerId,
        address nodeRunner,
        uint256 chainId
    ) private returns (uint256) {
        uint256 nodeRunnerId = _getNodeRunnerIdOrMint(nodeRunner, inputNodeRunnerId, chainId);
        uint256 total = scanners.length;
        uint256 scannersMigrated = 0;
        for (uint256 i = 0; i < total; i++) {
            uint256 scannerId = scannerNodeRegistry.scannerAddressToId(scanners[i]);
            if (scannerNodeRegistry.ownerOf(scannerId) != nodeRunner) revert SenderNotOwner(nodeRunner, scannerId);
            
            (string memory metadata, uint256 disabledFlags) = _checksScanner(scannerId, chainId, scanners[i]);

            if (!scannerNodeRegistry.optingOutOfMigration(scannerId)) {
                _migrateRegistries(scanners[i], disabledFlags, nodeRunnerId, chainId, metadata);
                {
                    stakeMigrator.migrate(SCANNER_SUBJECT, scannerId, NODE_RUNNER_SUBJECT, nodeRunnerId, nodeRunner);

                }
                scannersMigrated++;
            }
        }
        emit MigrationExecuted(scannersMigrated, total - scannersMigrated, nodeRunnerId, inputNodeRunnerId == NODE_RUNNER_NOT_MIGRATED);
        return nodeRunnerId;
    }

    function _checksScanner(uint256 scannerId, uint256 chainId, address scanner) private view returns (string memory metadata, uint256 disabledFlags) {
        (, , uint256 scannerChainId, string memory data, , uint256 flags) = scannerNodeRegistry.getScannerState(scannerId);
        if (scannerChainId != chainId) revert WrongScannerChainId(chainId, scannerChainId, scanner);
        return(data, flags);
    }


    function _migrateRegistries(
        address scanner,
        uint256 disabledFlags,
        uint256 nodeRunnerId,
        uint256 chainId,
        string memory metadata
    ) private {
        scannerPoolRegistry.registerMigratedScannerNode(
            ScannerPoolRegistryCore.ScannerNodeRegistration({ scanner: scanner, nodeRunnerId: nodeRunnerId, chainId: chainId, metadata: metadata, timestamp: block.timestamp }),
            disabledFlags != 0
        );
        scannerNodeRegistry.deregisterScannerNode(scannerNodeRegistry.scannerAddressToId(scanner));
        
    }

    function _getNodeRunnerIdOrMint(
        address nodeRunner,
        uint256 nodeRunnerId,
        uint256 chainId
    ) private returns (uint256) {
        if (nodeRunnerId == NODE_RUNNER_NOT_MIGRATED) {
            if (_migratedNodeRunners[chainId][nodeRunner] != 0) {
                revert NodeRunnerAlreadyMigrated(_migratedNodeRunners[chainId][nodeRunner]);
            } else {
                uint256 newNodeRunnerId = scannerPoolRegistry.registerMigratedNodeRunner(nodeRunner, chainId);
                _migratedNodeRunners[chainId][nodeRunner] = newNodeRunnerId;
                return newNodeRunnerId;
            }
        } else if (scannerPoolRegistry.ownerOf(nodeRunnerId) != nodeRunner) {
            revert NotOwnerOfNodeRunner(nodeRunner, nodeRunnerId);
        } else if (scannerPoolRegistry.monitoredChainId(nodeRunnerId) != chainId) {
            revert WrongNodeRunnerChainId(chainId, scannerPoolRegistry.monitoredChainId(nodeRunnerId), nodeRunnerId);
        }
        return nodeRunnerId;
    }
    uint256[48] private __gap;
}
