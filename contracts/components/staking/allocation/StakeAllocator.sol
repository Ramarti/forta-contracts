// SPDX-License-Identifier: UNLICENSED
// See Forta Network License: https://github.com/forta-network/forta-contracts/blob/master/LICENSE.md

pragma solidity ^0.8.9;

import "./IStakeAllocator.sol";
import "../SubjectTypeValidator.sol";
import "../FortaStakingUtils.sol";
import "../stakeSubjectHandling/IStakeSubjectHandler.sol";
import "../../BaseComponentUpgradeable.sol";
import "../../../tools/Distributions.sol";

/**
 * This contract also manages the allocation of stake. See SubjectTypeValidator.sol for in depth explanation of Subject Agency
 *
 * Stake constants:
 * totalStake = activeStake + inactiveStake
 * activeStake(delegated) = allocatedStake(delegated) + unallocatedStake(delegated)
 * activeStake(delegator) = allocatedStake(delegator) + unallocatedStake(delegator)
 * allocatedStake(managed) = (allocatedStake(delegated) + allocatedStake(delegator)) / totalManagedSubjects(delegated)
 * activeStake(managed) = inactiveStake(managed) = 0;
 *
 */
contract StakeAllocator is BaseComponentUpgradeable, SubjectTypeValidator, IStakeAllocator {
    using Distributions for Distributions.Balances;

    string public constant version = "0.1.0";
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakeSubjectHandler private immutable _subjectHandler;

    // subject => active stake
    Distributions.Balances private _allocatedStake;
    // subject => inactive stake
    Distributions.Balances private _unallocatedStake;

    event AllocatedStake(uint8 indexed subjectType, uint256 indexed subject, uint256 amount, uint256 totalAllocated);
    event UnallocatedStake(uint8 indexed subjectType, uint256 indexed subject, uint256 amount, uint256 totalAllocated);

    error SenderCannotAllocateFor(uint8 subjectType, uint256 subject);
    error CannotDelegateStakeUnderMin(uint8 subjectType, uint256 subject);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address forwarder, address subjectHandler) initializer ForwardedContext(forwarder) {
        if (subjectHandler == address(0)) revert ZeroAddress("subjectHandler");
        _subjectHandler = IStakeSubjectHandler(subjectHandler);
    }

    /**
     * @notice Initializer method, access point to initialize inheritance tree.
     * @param __manager address of AccessManager.
     */
    function initialize(address __manager) public initializer {
        __BaseComponentUpgradeable_init(__manager);
    }

    /************* External Views *************/

    /// Active stake allocated on subject
    function allocatedStakeFor(uint8 subjectType, uint256 subject) public view returns (uint256) {
        return _allocatedStake.balanceOf(FortaStakingUtils.subjectToActive(subjectType, subject));
    }

    /// Total allocated stake in all managed subjects, both from delegated and delegator. Only returns values from
    /// DELEGATED types, else 0.
    function allocatedManagedStake(uint8 subjectType, uint256 subject) public view returns (uint256) {
        if (getSubjectTypeAgency(subjectType) == SubjectStakeAgency.DELEGATED) {
            return
                _allocatedStake.balanceOf(FortaStakingUtils.subjectToActive(subjectType, subject)) +
                _allocatedStake.balanceOf(FortaStakingUtils.subjectToActive(getDelegatorSubjectType(subjectType), subject));
        }
        return 0;
    }

    /// Returns allocatedManagedStake (own + delegator's) in DELEGATED / total managed subjects, or 0 if not DELEGATED
    function allocatedStakePerManaged(uint8 subjectType, uint256 subject) external view returns (uint256) {
        if (getSubjectTypeAgency(subjectType) != SubjectStakeAgency.DELEGATED) {
            return 0;
        }
        return allocatedManagedStake(subjectType, subject) / _subjectHandler.totalManagedSubjects(subjectType, subject);
    }

    /// Returns allocatedManagedStake (own only) in DELEGATED / total managed subjects, or 0 if not DELEGATED
    function allocatedOwnStakePerManaged(uint8 subjectType, uint256 subject) public view returns (uint256) {
        if (getSubjectTypeAgency(subjectType) != SubjectStakeAgency.DELEGATED) {
            return 0;
        }
        return allocatedStakeFor(subjectType, subject) / _subjectHandler.totalManagedSubjects(subjectType, subject);
    }

    /// Returns allocatedManagedStake (delegators only) in DELEGATED / total managed subjects, or 0 if not DELEGATED
    function allocatedDelegatorsStakePerManaged(uint8 subjectType, uint256 subject) public view returns (uint256) {
        if (getSubjectTypeAgency(subjectType) != SubjectStakeAgency.DELEGATED) {
            return 0;
        }
        return allocatedStakeFor(getDelegatorSubjectType(subjectType), subject) / _subjectHandler.totalManagedSubjects(subjectType, subject);
    }

    /// Total active stake not allocated on subjects
    function unallocatedStakeFor(uint8 subjectType, uint256 subject) external view returns (uint256) {
        return _unallocatedStake.balanceOf(FortaStakingUtils.subjectToActive(subjectType, subject));
    }

    /************* Manual allocations *************/

    /**
     * @notice owner of a DELEGATED subject moves tokens from its own unallocated to allocated.
     * It will fail if allocating more than the max for managed stake.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of stake to move from unallocated to allocated.
     */
    function allocateOwnStake(
        uint8 subjectType,
        uint256 subject,
        uint256 amount
    ) external onlyAgencyType(subjectType, SubjectStakeAgency.DELEGATED) {
        if (!_subjectHandler.canManageAllocation(subjectType, subject, _msgSender())) revert SenderCannotAllocateFor(subjectType, subject);
        _allocateStake(subjectType, subject, _msgSender(), amount);
    }

    /**
     * @notice owner of a DELEGATED subject moves it's own tokens from allocated to unallocated.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of incoming staked token.
     */
    function unallocateOwnStake(
        uint8 subjectType,
        uint256 subject,
        uint256 amount
    ) external onlyAgencyType(subjectType, SubjectStakeAgency.DELEGATED) {
        if (!_subjectHandler.canManageAllocation(subjectType, subject, _msgSender())) revert SenderCannotAllocateFor(subjectType, subject);
        _unallocateStake(subjectType, subject, amount);
    }

    /**
     * @notice owner of a DELEGATED subject moves tokens from DELEGATOR's unallocated to allocated.
     * It will fail if allocating more than the max for managed stake.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of stake to move from unallocated to allocated.
     */
    function allocateDelegatorStake(
        uint8 subjectType,
        uint256 subject,
        uint256 amount
    ) external onlyAgencyType(subjectType, SubjectStakeAgency.DELEGATED) {
        if (!_subjectHandler.canManageAllocation(subjectType, subject, _msgSender())) revert SenderCannotAllocateFor(subjectType, subject);
        _allocateStake(getDelegatorSubjectType(subjectType), subject, _msgSender(), amount);
    }

    /**
     * @notice owner of a DELEGATED subject moves it's own tokens from allocated to unallocated.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of staked token.
     */
    function unallocateDelegatorStake(
        uint8 subjectType,
        uint256 subject,
        uint256 amount
    ) external onlyAgencyType(subjectType, SubjectStakeAgency.DELEGATED) {
        if (!_subjectHandler.canManageAllocation(subjectType, subject, _msgSender())) revert SenderCannotAllocateFor(subjectType, subject);
        _unallocateStake(getDelegatorSubjectType(subjectType), subject, amount);
    }

    /**
     * @notice moves tokens from unallocatedStake to allocatedStake if possible.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of staked token.
     */
    function _allocateStake(
        uint8 subjectType,
        uint256 subject,
        address allocator,
        uint256 amount
    ) private {
        uint256 activeSharesId = FortaStakingUtils.subjectToActive(subjectType, subject);
        if (_unallocatedStake.balanceOf(activeSharesId) < amount) revert AmountTooLarge(amount, _unallocatedStake.balanceOf(activeSharesId));
        (int256 extra, uint256 max) = _allocationIncreaseChecks(subjectType, subject, SubjectStakeAgency.DELEGATED, allocator, amount);
        if (extra > 0) revert AmountTooLarge(amount, max);
        _allocatedStake.mint(activeSharesId, amount);
        _unallocatedStake.burn(activeSharesId, amount);
        emit AllocatedStake(subjectType, subject, amount, _allocatedStake.balanceOf(activeSharesId));
    }

    /**
     * @notice moves tokens from allocatedStake to unallocatedStake if possible.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of staked token.
     */
    function _unallocateStake(
        uint8 subjectType,
        uint256 subject,
        uint256 amount
    ) private {
        uint256 activeSharesId = FortaStakingUtils.subjectToActive(subjectType, subject);
        if (_allocatedStake.balanceOf(activeSharesId) < amount) revert AmountTooLarge(amount, _allocatedStake.balanceOf(activeSharesId));
        _allocatedStake.burn(activeSharesId, amount);
        _unallocatedStake.mint(activeSharesId, amount);
        emit UnallocatedStake(subjectType, subject, amount, _unallocatedStake.balanceOf(activeSharesId));
    }

    /************* When incrementing/decrementing activeStake (IStakeAllocator) *************/

    /**
     * @notice Allocates stake on deposit (increment of activeStake) for a DELEGATED subject incrementing it's allocatedStake.
     * If allocatedStake is going to be over the max
     * for the corresponding MANAGED subject, the excess increments unallocatedStake.
     * @param activeSharesId ERC1155 id representing the active shares of a subject / subjectType pair.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of incoming staked token.
     */
    function depositAllocation(
        uint256 activeSharesId,
        uint8 subjectType,
        uint256 subject,
        address allocator,
        uint256 amount
    ) external override onlyRole(STAKE_ALLOCATOR_ACCESS) {
        SubjectStakeAgency agency = getSubjectTypeAgency(subjectType);
        if (agency != SubjectStakeAgency.DELEGATED && agency != SubjectStakeAgency.DELEGATOR) {
            return;
        }

        (int256 extra, ) = _allocationIncreaseChecks(subjectType, subject, agency, allocator, amount);
        if (extra > 0) {
            _allocatedStake.mint(activeSharesId, amount - uint256(extra));
            emit AllocatedStake(subjectType, subject, amount - uint256(extra), _allocatedStake.balanceOf(activeSharesId));
            _unallocatedStake.mint(activeSharesId, uint256(extra));
            emit UnallocatedStake(subjectType, subject, uint256(extra), _unallocatedStake.balanceOf(activeSharesId));
        } else {
            _allocatedStake.mint(activeSharesId, amount);
            emit AllocatedStake(subjectType, subject, amount, _allocatedStake.balanceOf(activeSharesId));
        }
    }

    /**
     * @notice method to call when substracting activeStake. Will burn unallocatedStake (and allocatedStake if amount is bigger than unallocatedStake)
     * @param activeSharesId ERC1155 id representing the active shares of a subject / subjectType pair.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param amount amount of incoming staked token.
     */
    function withdrawAllocation(
        uint256 activeSharesId,
        uint8 subjectType,
        uint256 subject,
        uint256 amount
    ) external onlyRole(STAKE_ALLOCATOR_ACCESS) {
        int256 fromAllocated = int256(_unallocatedStake.balanceOf(activeSharesId)) - int256(amount);
        if (fromAllocated < 0) {
            _allocatedStake.burn(activeSharesId, uint256(-fromAllocated));
            _unallocatedStake.burn(activeSharesId, _unallocatedStake.balanceOf(activeSharesId));
        } else {
            _unallocatedStake.burn(activeSharesId, amount);
        }
        emit UnallocatedStake(subjectType, subject, amount, _unallocatedStake.balanceOf(activeSharesId));
    }

    /**
     * @notice Checks if:
     *  - incoming allocation will go over managed subject stakeThreshold.max
     *  - if DELEGATED, reverts if sender is not the owner of the relevant registry,.
     *  - if DELEGATOR, reverts if DELEGATED has not staked over stakeThreshold.min of managed subject.
     * @param subjectType type id of Stake Subject. See SubjectTypeValidator.sol
     * @param subject id identifying subject (external to FortaStaking).
     * @param agency of the subjectType
     * @param amount of tokens to be allocated.
     * @return extra amount of tokens over the managed stakeThreshold.max
     * @return max stakeThreshold.max / totalManagedSubjects
     */
    function _allocationIncreaseChecks(
        uint8 subjectType,
        uint256 subject,
        SubjectStakeAgency agency,
        address allocator,
        uint256 amount
    ) private view returns (int256 extra, uint256 max) {
        uint256 subjects = 0;
        uint256 maxPerManaged = 0;
        uint256 currentlyAllocated = 0;
        if (agency == SubjectStakeAgency.DELEGATED) {
            // i.e NodeRunnerRegistry
            if (!_subjectHandler.canManageAllocation(subjectType, subject, allocator)) revert SenderCannotAllocateFor(subjectType, subject);
            subjects = _subjectHandler.totalManagedSubjects(subjectType, subject);
            maxPerManaged = _subjectHandler.maxManagedStakeFor(subjectType, subject);
            currentlyAllocated = allocatedManagedStake(subjectType, subject);
        } else if (getSubjectTypeAgency(subjectType) == SubjectStakeAgency.DELEGATOR) {
            // i.e Delegator to NodeRunnerRegistry
            subjects = _subjectHandler.totalManagedSubjects(getDelegatedSubjectType(subjectType), subject);
            maxPerManaged = _subjectHandler.maxManagedStakeFor(getDelegatedSubjectType(subjectType), subject);
            // If DELEGATED has staked less than minimum stake, revert cause delegation not unlocked
            if (allocatedStakeFor(getDelegatedSubjectType(subjectType), subject) / subjects <= maxPerManaged) {
                revert CannotDelegateStakeUnderMin(getDelegatedSubjectType(subjectType), subject);
            }
            currentlyAllocated = allocatedManagedStake(getDelegatedSubjectType(subjectType), subject);
        }

        return (int256(currentlyAllocated + amount) - int256(maxPerManaged * subjects), maxPerManaged * subjects);
    }
}