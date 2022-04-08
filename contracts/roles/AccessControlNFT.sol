// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./LibRoles.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AccessControlNFT is ERC721Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using LibRoles for User;
    using LibRoles for RoleData;

    uint256 constant PERCENT = 100;

    uint256 constant ORACLE_DECIMALS = 10 ** 8;

    address internal _revenueSplitter;
    address internal constant WMATIC_ADDRESS = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address internal _mghWMaticPair;

    // signals whether the transfer is transferable, it is always mintable
    bool internal _isTransferable;

    struct User {
        UserRoleData[] userRoleDataArray;
        mapping(uint8 => uint256) indexByRole;
    }

    struct RoleData {
        // if false, the role cannot be purchased
        bool isActive;
        // amount of seconds per interval
        uint40 intervalLength;  // => cannot be 0 !! => every role has some kind of time limit
        // total calls per interval
        uint40 callsPerInterval;  // => 0 means unlimited calls
/*         uint40 maxCallsInAdvance; // the maximum amount of calls a user can book for this role */
        uint16 maxIntervalsAtOnce;
        uint8 maxRebate;
        uint8 rebatePerInterval;
        mapping(Tier => uint256) feeByTier;
    }

    enum Tier {
        NO_TIER,
        ONE,
        TWO,
        THREE,
        FOUR,
        FIVE,
        SIX,
        SEVEN,
        EIGHT,
        NINE,
        TEN
    }

    struct UserRoleData {
        uint8 role;
        Tier tier;
        uint40 expiration;
        uint40 callsTotal;
        uint40 callsUsedTotal;
    }

    struct CurrencyData {
        AggregatorV3Interface oracle;
        uint256 decimals;
    }

    struct RoleSetup {
        uint8 roleId;
        bool isActive;
        uint40 intervalLength; 
        uint40 callsPerInterval;
        uint16 maxIntervalsAtOnce;
        uint8 maxRebate;
        uint8 rebatePerInterval;
    }

    mapping(address => User) _user;
    mapping(uint8 => RoleData) _roleData;
    mapping(address => CurrencyData) _currencyData;

    modifier roleInitialized(uint8 roleId) {
        require(_roleData[roleId].intervalLength != 0, "not setup yet");
        _;
    }

    // auto initialize the contract, since it will serve as the implementation for a proxy
    constructor() initializer {}

    function initialize(
        RoleSetup memory rolesSetupData,
        Tier[] memory enabledTiers,
        uint256[] memory feeByTier,
        address[] memory currencies,
        address revenueSplitter,
        address mghWMaticPair
    ) external initializer {
        __Ownable_init();
        __ERC721_init("API", "API");

        setupRole(rolesSetupData, enabledTiers, feeByTier);
        for(uint256 i = 0; i < currencies.length; i = i + 2) {
            setCurrency(currencies[i], AggregatorV3Interface(currencies[i+1]));
        }
        _revenueSplitter = revenueSplitter;
        _mghWMaticPair = mghWMaticPair;
    }

    function _mint(address recipient) internal {
        _mint(recipient, (uint160(recipient)));
    }

    function purchaseRole(
        address recipient,
        uint8   roleId,
        Tier    tier,
        address currency,
        uint40  intervals
    ) public payable {

        RoleData storage roleData = _roleData[roleId];
        User storage user = _user[recipient];
        CurrencyData memory currencyData = _currencyData[currency];

        uint256 userRoleIndex = user.roleIndex(roleId);
        uint256 feeForTier = roleData.feeByTier[tier];
        uint256 amountToPayInUSD = intervals * feeForTier;

        require(feeForTier != 0, "tier not active");
        require(roleData.isActive, "role not active");
        require(intervals <= roleData.maxIntervalsAtOnce, "too many intervals");

        require(address(currencyData.oracle) != address(0), "currency not accepted");
        if(msg.value > 0) require(currency == address(0), "for native token specify 0 address as currency");

        // calculate fee: 
        // if user doesnt have the role, push it in array, otherwise update it in storage
        if (userRoleIndex == type(uint256).max) {
            require(intervals > 0, "amount to purchase cannot be 0");

            user.indexByRole[roleId] = user.userRoleDataArray.length;
            user.addRole(
                UserRoleData(
                    roleId,
                    tier,
                    uint40(block.timestamp) + intervals * roleData.intervalLength,
                    intervals * roleData.callsPerInterval,
                    0
                )
            );
        } else {
            // if(! currentTier == tier)
            // user already has the role, so we deduct from payment, 
            // if new tier is lower and add upgrade fee, if new tier is higher
            UserRoleData storage userRoleData = user.userRoleDataArray[userRoleIndex];
            uint256 intervalsLeft_100 = _intervalsLeft_100(roleData.intervalLength, userRoleData.expiration);
            Tier currentTier = userRoleData.tier;
            // case 1: user downgrades tier
            if(currentTier > tier) {
                // case 1.1: user downgrades tier
                uint256 refundAmount = intervalsLeft_100 * (roleData.feeByTier[currentTier] - feeForTier) / PERCENT;
                amountToPayInUSD = refundAmount >= amountToPayInUSD ? 0 : amountToPayInUSD - refundAmount;

            // case 2: user upgrades tier
            } else {
                amountToPayInUSD += intervalsLeft_100 * (feeForTier - roleData.feeByTier[currentTier]);
            }

            // now update the user role data:
            userRoleData.callsTotal += intervals * roleData.callsPerInterval;
            userRoleData.expiration += intervals * roleData.intervalLength;
            userRoleData.tier = tier;
        }

        // check if rebate is applicable, if so, apply it with a maximum of `maxRebate`
        if(intervals > 1 && roleData.rebatePerInterval != 0) {
            uint256 rebatePercentage = intervals * uint256(roleData.rebatePerInterval);
            rebatePercentage = rebatePercentage > roleData.maxRebate ? roleData.maxRebate : rebatePercentage;
            amountToPayInUSD = amountToPayInUSD * (PERCENT - rebatePercentage) / PERCENT;
        }

        uint256 amountToPayInCurrency = amountToPayInUSD * ORACLE_DECIMALS * currencyData.decimals / _getLatestPrice(currencyData.oracle);

        if(balanceOf(recipient) == 0) _mint(recipient);

        if (_msgSender() == owner()) return;

        if(currency == address(0)) {
            require(msg.value >= amountToPayInCurrency, "not enough native currency sent");
            _revenueSplitter.call{ value: address(this).balance }("");
        } else {
            IERC20(currency).safeTransferFrom(_msgSender(), _revenueSplitter, amountToPayInCurrency);
        }
    }

    function purchaseRoleForSelf(uint8 role, Tier tier, address currency, uint40 intervals) public {
        purchaseRole(_msgSender(), role, tier, currency, intervals);
    }


    //// OWNER ////

    function setupRole(
        RoleSetup memory roleSetup,
        Tier[] memory enabledTiers,
        uint256[] memory feeByTier
    ) public onlyOwner {
        RoleData storage role = _roleData[roleSetup.roleId];

        require(role.intervalLength == 0, "already setup");
        require(roleSetup.intervalLength > 0 && roleSetup.maxIntervalsAtOnce > 0, "non zero param is given as 0");
        require(enabledTiers.length == feeByTier.length, "tier fees dont match");
        require(roleSetup.maxRebate <= 100);

        role.isActive           = roleSetup.isActive;
        role.callsPerInterval   = roleSetup.callsPerInterval;
        role.intervalLength     = roleSetup.intervalLength;
        role.maxIntervalsAtOnce = roleSetup.maxIntervalsAtOnce;
        role.maxRebate          = roleSetup.maxRebate;
        role.rebatePerInterval  = roleSetup.rebatePerInterval;

        for(uint256 i = 0; i < enabledTiers.length; i++) {
            require(feeByTier[i] != 0, "fee cannot be 0");
            require(enabledTiers[i] != Tier.NO_TIER, "cannot set the NO_TIER");
            role.feeByTier[enabledTiers[i]] = feeByTier[i];
        }
        // emit
    }

    function setFee(uint8 roleId, Tier tier, uint256 feeForTier) public onlyOwner roleInitialized(roleId) {
        _roleData[roleId].feeByTier[tier] = feeForTier;
    }

    function setRoleStatus(uint8 roleId, bool isActive) public onlyOwner roleInitialized(roleId) {
        require(isActive != _roleData[roleId].isActive, "already set");
         _roleData[roleId].isActive = isActive;
    }

    /// careful, the fee is per interval, so this might effectively change the price
    function setIntervalLength(uint8 roleId, uint40 newIntervalLength) public onlyOwner roleInitialized(roleId) {
        require(newIntervalLength != 0);
        _roleData[roleId].intervalLength = newIntervalLength;
    }

    function setCallsPerInterval(uint8 roleId, uint40 callsPerInterval) public onlyOwner roleInitialized(roleId) {
        _roleData[roleId].callsPerInterval = callsPerInterval;
    }

    function setMaxIntervalsAtOnce(uint8 roleId, uint16 newMaxIntervals) public onlyOwner roleInitialized(roleId) {
        require(newMaxIntervals != 0);
        _roleData[roleId].maxIntervalsAtOnce = newMaxIntervals;
    }

    function setRebate(uint8 roleId, uint8 rebatePerInterval, uint8 maxRebate) public onlyOwner roleInitialized(roleId) {
        require(maxRebate <= 100);
        RoleData storage role = _roleData[roleId];
        role.rebatePerInterval = rebatePerInterval;
        role.maxRebate = maxRebate;
    }

    function setCurrency(address currency, AggregatorV3Interface oracle) public onlyOwner {
        require(_getLatestPrice(oracle) > 0, "oracle contract call failed");
        uint256 decimals;
        if(currency == address(0)) {
            decimals = 10 ** 18;
        } else {
            decimals = 10 ** IERC20Metadata(currency).decimals();
        }
        _currencyData[currency] = CurrencyData(oracle, decimals);
    }

    function setUsedCalls(address account, uint8 roleId, uint40 callsUsedTotal) public onlyOwner {
        uint256 index = _user[account].indexByRole[roleId]; 
        _user[account].userRoleDataArray[index].callsUsedTotal = callsUsedTotal;
    }

    function setTransferability(bool isTransferable) public onlyOwner {
        require(isTransferable != _isTransferable, "already set");
        _isTransferable = isTransferable;
    }

    function setRevenueSplitter(address revenueSplitter) public onlyOwner {
        _revenueSplitter = revenueSplitter;
    }

    function setMghPool(address pairContract) public onlyOwner {
        _mghWMaticPair = pairContract;
    }


    //// VIEWS ////

    function getRoleInfo(uint8 roleId) external view returns(bool isActive, uint40 intervalLength, uint40 callsPerInterval) {
        RoleData storage role = _roleData[roleId];
        isActive = role.isActive;
        intervalLength = role.intervalLength;
        callsPerInterval = role.callsPerInterval;
    }

    function getTierInfo(uint8 roleId, Tier tier) external view returns(bool isActive, uint256 fee) {
        RoleData storage role = _roleData[roleId];
        fee = role.feeByTier[tier];
        isActive = role.isActive && fee != 0;
    }


    function getUserRoleSingle(address account, uint8 roleId) external view returns(bytes32 ret) {
        uint256 mapSlot;
        uint256 userRoleIndex = _user[account].roleIndex(roleId);
        if(userRoleIndex == type(uint256).max) return bytes32(userRoleIndex);
        assembly {
            mapSlot := _user.slot
        }
        uint256 arrayLengthSlot = uint256(keccak256(abi.encodePacked(uint256(uint160(account)), mapSlot)));
        uint256 roleSlot = uint256(keccak256(abi.encodePacked(arrayLengthSlot))) + userRoleIndex;
        assembly {
            ret := sload(roleSlot)
        }
    }

    function getUserRolesComplete(address account) public view returns(bytes32[] memory ret) {
        uint256 mapSlot;
        assembly {
            mapSlot := _user.slot
        }
        uint256 arrayLengthSlot = uint256(keccak256(abi.encodePacked(uint256(uint160(account)), mapSlot)));
        uint256 firstElementSlot = uint256(keccak256(abi.encodePacked(arrayLengthSlot)));
        uint256 length;
        assembly {
            length := sload(arrayLengthSlot)
        }
        ret = new bytes32[](length);
        for(uint256 i = 0; i < length; i++) {
            uint256 arrayElementSlot = firstElementSlot + i;
            bytes32 slotData;
            assembly {
                slotData := sload(arrayElementSlot)
            }
            ret[i] = slotData;
        }
    }

    function getNFTRolesComplete(uint256 tokenId) public view returns(UserRoleData[] memory) {
        require(_exists(tokenId), "token not minted");
        return _user[address(uint160(tokenId))].userRoleDataArray;
    }

    function getCurrencyInfo(address currency) public view returns(CurrencyData memory) {
        return _currencyData[currency];
    }
    
    function _intervalsLeft_100(uint256 intervalLength, uint256 expiration) internal view returns(uint256) {
        if (expiration <= block.timestamp) return 0;
        
        uint256 timeLeft = expiration - block.timestamp;
        return timeLeft * PERCENT / intervalLength;
    }

    function _getLatestPrice(AggregatorV3Interface oracle) public view returns(uint256) {
        // if token is MGH (no oracle provider) we calculate based on the Quickswap LP
        if(address(oracle) == _mghWMaticPair) {
            (uint112 wmatic_reserve, uint112 mgh_reserve, ) = IUniswapV2Pair(_mghWMaticPair).getReserves();
            (, int maticPrice,,,) = _currencyData[address(0)].oracle.latestRoundData();
            if(maticPrice <= 0) revert("invalid price feed");
            // both tokens have 18 decimals, the 8 oracle decimal places are included in `maticPrice`
            return uint256(maticPrice) * wmatic_reserve / mgh_reserve;
        }
        (, int price,,,) = oracle.latestRoundData();
        if(price <= 0) revert("invalid price feed");
        return uint256(price);
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId);

        if(_isTransferable) return;

        require(from == address(0) || to == address(0), "not transferable at the moment");
    }
}