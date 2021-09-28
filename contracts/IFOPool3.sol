// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';  
import '@pancakeswap/pancake-swap-lib/contracts/utils/ReentrancyGuard.sol';
import '@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol';

contract IFOforPool3 is ReentrancyGuard {
  
  using SafeMath for uint256;
  
  AggregatorV3Interface internal priceFeed;

  // Info of each user.uu
  struct UserInfo {
      uint256 amount;   // How many tokens the user has provided.
      bool claimed;  // default false
  }

  // admin address
  address public adminAddress;
  // The raising token
  ERC20 public lpToken;
  // The offering token
  ERC20 public offeringToken;
  // The block number when IFO starts
  uint256 public startBlock;
  // The block number when IFO ends
  uint256 public endBlock;
  // total amount of offeringToken that will offer
  uint256 public offeringAmount;
  // total amount of raising tokens that have already raised
  uint256 public totalAmount;
  // address => amount
  mapping (address => UserInfo) public userInfo;
  // participators
  address[] public addressList;

  event Deposit(address indexed user, uint256 amount); 
  event Harvest(address indexed user, uint256 offeringAmount);

  constructor(
      ERC20 _lpToken,
      ERC20 _offeringToken,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _offeringAmount
  ) public {
      lpToken = _lpToken;
      offeringToken = _offeringToken;
      startBlock = _startBlock;
      endBlock = _endBlock;
      offeringAmount = _offeringAmount;
      totalAmount = 0;
      adminAddress = msg.sender;
      priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
  }

  modifier onlyAdmin() {
    require(msg.sender == adminAddress, "admin: wut?");
    _;
  }

  //just security features, necessary?  
  function setOfferingAmount(uint256 _offerAmount) public onlyAdmin {
    require (block.number < startBlock, 'no');
    
    offeringAmount = _offerAmount;
  }

  function deposit(uint256 _amount) public payable {
    require (block.number > startBlock && block.number < endBlock, 'not ifo time');
    require (_amount > 0 || msg.value > 0, 'send ETH or USDT (> 0)');
    
    if (userInfo[msg.sender].amount == 0) {
      addressList.push(address(msg.sender));
    }
    if (msg.value == 0) {
    lpToken.transferFrom(address(msg.sender), address(this), _amount);
    userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(_amount);
    totalAmount = totalAmount.add(_amount);
    emit Deposit(msg.sender, _amount);
    }
    else {
    uint256 etheramount = msg.value.div(1e18);
    uint256 __amount = etheramount.mul(uint(getThePrice()));
    userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(__amount);
    totalAmount = totalAmount.add(__amount);
    emit Deposit(msg.sender, __amount);
    }
  }

  function harvest() public nonReentrant {
    require (block.number > endBlock, 'not harvest time');
    require (userInfo[msg.sender].amount > 0, 'have you participated?');
    require (!userInfo[msg.sender].claimed, 'nothing to harvest');

    uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
    offeringToken.transfer(address(msg.sender), offeringTokenAmount);

    userInfo[msg.sender].claimed = true;
    
    emit Harvest(msg.sender, offeringTokenAmount);
  }

  function hasHarvest(address _user) external view returns(bool) {
      return userInfo[_user].claimed;
  }

  /* 
  function getUserAllocation(address _user) public view returns(uint256) {
    return userInfo[_user].amount.mul(1e12).div(totalAmount).div(1e6);
  }
*/
  // get the amount of IFO token you will get
  function getOfferingAmount(address _user) public view returns(uint256) {
      uint256 allocation = userInfo[_user].amount.div(totalAmount);
      return offeringAmount.mul(allocation);
  }

  /* get the amount of lp token you will be refunded NOT NEEDED
  function getRefundingAmount(address _user) public view returns(uint256) {
    if (totalAmount <= raisingAmount) {
      return 0;
    }
    uint256 allocation = getUserAllocation(_user);
    uint256 payAmount = raisingAmount.mul(allocation).div(1e6);
    return userInfo[_user].amount.sub(payAmount);
  }
  */
  function getAddressListLength() external view returns(uint256) {
    return addressList.length;
  }

  function finalWithdraw(uint256 _lpAmount, uint256 _offerAmount) public onlyAdmin {
    require (_lpAmount < lpToken.balanceOf(address(this)), 'not enough token 0');
    require (_offerAmount < offeringToken.balanceOf(address(this)), 'not enough token 1');
    
    lpToken.transfer(address(msg.sender), _lpAmount);
    offeringToken.transfer(address(msg.sender), _offerAmount);
  }
  
  //Function to get the ETH price in USD
  function getThePrice() public view returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }
}
