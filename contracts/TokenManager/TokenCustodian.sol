// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../vesting/Interfaces/IVestingFlex.sol";

contract TokenCustodian is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    event Retrieved(Branch indexed branch, uint256 amount);

    IERC20 public TOKEN;
    IVestingFlex public vest;

    bytes32[3] private BRANCH_HASHES = [
        keccak256("STRATEGIC_SALE"),
        keccak256("WORKING_GROUPS"),
        keccak256("ECOSYSTEM_GRANTS")
    ];

    uint256 public immutable STRATEGIC_SALE_TOTAL = 1;
    uint256 public immutable WORKING_GROUPS_TOTAL = 1;
    uint256 public immutable ECOSYSTEM_GRANTS_TOTAL = 1;

    enum Branch {
        STRATEGIC_SALE,
        WORKING_GROUPS,
        ECOSYSTEM_GRANTS
    }

    mapping(Branch => uint256) public balanceOfBranch;

    constructor(
        address admin
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function retrieve(Branch branch, uint256 amount, bool claimPending) external onlyRole(BRANCH_HASHES[uint256(branch)]) {
        if(claimPending) {
            uint256 claimed  = vest.retrieve(uint256(branch));
            balanceOfBranch[branch] += claimed;
        }
        balanceOfBranch[branch] -= amount;
        _processPayment(address(this), msg.sender, amount);
        emit Retrieved(branch, amount);
    }

    /// VIEW
    function totalAllocation(Branch branch) public pure returns(uint256) {
        if(branch == Branch.STRATEGIC_SALE)   return STRATEGIC_SALE_TOTAL;
        if(branch == Branch.WORKING_GROUPS)   return WORKING_GROUPS_TOTAL;
        if(branch == Branch.ECOSYSTEM_GRANTS) return ECOSYSTEM_GRANTS_TOTAL;
        return 0;
    }

    function totalReserves(Branch branch) public view returns(uint256) {
        return totalAllocation(branch) + balanceOfBranch[branch] - vest.getClaimed(address(this), uint256(branch));
    }

    function totalUsedInBranch(Branch branch) external view returns(uint256) {
        return vest.getClaimed(address(this), uint256(branch)) - balanceOfBranch[branch];
    }

    function availableInBranch(Branch branch) public view returns(uint256) {
        return balanceOfBranch[branch] + vest.getClaimableNow(address(this), uint256(branch));
    }

    function availableInBranchAtTimestamp(Branch branch, uint256 when) public view returns(uint256) {
        return balanceOfBranch[branch] + vest.getClaimableAtTimestamp(address(this), uint256(branch), when);
    }

    function BRANCHES() external pure returns(uint256, string memory, uint256, string memory, uint256, string memory) {
        return (0, "STRATEGIC_SALE", 1, "WORKING_GROUPS", 2, "ECOSYSTEM_GRANTS");
    }

    /// INTERNAL
    function _processPayment(address from, address to, uint256 amount) internal {
        TOKEN.safeTransferFrom(from, to, amount);
    }
}