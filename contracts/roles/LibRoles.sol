pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./AccessControlNFT.sol";

library LibRoles {

    function isTierEnabled(AccessControlNFT.RoleData storage role, AccessControlNFT.Tier tier) internal view returns(bool) {
        return role.feeByTier[tier] > 0;
    }

    function hasRole(AccessControlNFT.User storage user, uint8 roleId) internal view returns(bool) {
        return roleIndex(user, roleId) != type(uint256).max;
    }

    function roleIndex(AccessControlNFT.User storage user, uint8 roleId) internal view returns(uint256) {
        uint256 index = user.indexByRole[roleId];
        return index == 0 ? type(uint256).max : index;
    }

    function bestTierOf(AccessControlNFT.User storage user, uint8 roleId) internal view returns(AccessControlNFT.Tier) {
        return user.userRoleDataArray[user.indexByRole[roleId]].tier;
    }

    function addRole(AccessControlNFT.User storage user, AccessControlNFT.UserRoleData memory roleData) internal {
        user.userRoleDataArray.push(roleData);
    }
}