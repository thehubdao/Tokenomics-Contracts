// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract IFOPool2 is ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // Info of each user.uu
  struct UserInfo {
      uint256 amount;   // How many tokens the user has provided.
      bool claimed;  // default false
  }

  // admin address
  address public adminAddress;
  // The raising token
  IERC20 public lpToken;
  // The offering token
  IERC20 public offeringToken;
  // The block number when IFO starts
  uint256 public startBlock;
  // The block number when IFO ends
  uint256 public endBlock;
  // min. Price
  uint256 public priceA;                          // price in LPtoken/MGH 
  // max. Price 
  uint256 public priceB;
  // total amount of offeringToken that will offer
  uint256 public offeringAmount;
  // total amount of raising tokens that have already raised
  uint256 public totalAmount;
  // address => amount
  mapping (address => UserInfo) public userInfo;
  // participators
  address[] public addressList;


  event Deposit(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

  constructor(
      IERC20 _lpToken,
      IERC20 _offeringToken,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _offeringAmount,
      uint256 _priceA,
      uint256 _priceB
  ) public {
      lpToken = _lpToken;
      offeringToken = _offeringToken;
      startBlock = _startBlock;
      endBlock = _endBlock;
      offeringAmount = _offeringAmount;
      priceA = _priceA;
      priceB = _priceB;
      totalAmount = 0;
      adminAddress = msg.sender;
  }

  modifier onlyAdmin() {
    require(msg.sender == adminAddress, "admin: wut?");
    _;
  }

  modifier HarvestTime() {
    require(block.number > endBlock, 'not harvest time yet!');
    _;
  }

  function deposit(uint256 _amount) public payable {
    require (block.number > startBlock && block.number < endBlock, 'not ifo time');
    require (_amount > 0, 'need _amount > 0');
    lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
    if (userInfo[msg.sender].amount == 0) {
      addressList.push(address(msg.sender));
    }
    userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(_amount);
    totalAmount = totalAmount.add(_amount);
    emit Deposit(msg.sender, _amount);
  }

  function harvest() public nonReentrant HarvestTime {
    require (userInfo[msg.sender].amount > 0, 'have you participated?');
    require (!userInfo[msg.sender].claimed, 'nothing to harvest');
    userInfo[msg.sender].claimed = true;
    uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
    uint256 refundingTokenAmount = getRefundingAmount(msg.sender);
    offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
    if (refundingTokenAmount > 0) {
      lpToken.safeTransfer(address(msg.sender), refundingTokenAmount);
    }
    emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
  }

  // allocation 10^7 means 0.1(10%), 1 means 10^(-8)(0.000001%), 10^8 means 1(100%),
  function getUserAllocation(address _user) public view returns(uint256) {
    return userInfo[_user].amount.mul(1e14).div(totalAmount).div(1e6);
  }

  // get the amount of IFO token you will get
  function getOfferingAmount(address _user) public view returns(uint256) {
    if (totalAmount > offeringAmount.mul(priceA)) {
      uint256 allocation = getUserAllocation(_user);
      return offeringAmount.mul(allocation).div(1e8);
    }
    else {
      return userInfo[_user].amount.div(priceA);
    }
  }

  // get the amount of lp token you will be refunded
  function getRefundingAmount(address _user) public view returns(uint256) {
    if (totalAmount <= offeringAmount.mul(priceB)) {
      return 0;
    }
    else{
      uint256 receivedAmount = getOfferingAmount(msg.sender);
      uint256 compensatedAmount = receivedAmount.mul(priceB);
      return userInfo[_user].amount.sub(compensatedAmount);
    }
  }

  /*
  function hasHarvest(address _user) external view HarvestTime  returns(bool) {
    return userInfo[_user].claimed;
  }

  function getAddressListLength() external view returns(uint256) {
    return addressList.length;
  }
  */

 //admin can withdraw after ~ 2 weeks
  function finalWithdraw(uint256 _lpAmount, uint256 _offerAmount) public onlyAdmin {
    require ( block.number > endBlock.add(1e7) );
    require (_lpAmount <= lpToken.balanceOf(address(this)), 'not enough LP token');
    require (_offerAmount <= offeringToken.balanceOf(address(this)), 'not enough offering token');
    lpToken.safeTransfer(address(msg.sender), _lpAmount);
    offeringToken.safeTransfer(address(msg.sender), _offerAmount);
  }
}