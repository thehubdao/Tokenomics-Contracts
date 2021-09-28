// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract IFOPool1 is ReentrancyGuard {
  using SafeERC20 for IERC20;

  // The raising token
  IERC20 public lpToken;
  // The offering token
  IERC20 public offeringToken;
  // The block number when IFO starts
  uint256 public startBlock;
  // The block number when IFO ends
  uint256 public endBlock;
  // total amount of raising tokens that can be raised (USDT)
  uint256 public raisingAmount;
  // total amount of offeringToken that will offer (MGH)
  uint256 public offeringAmount;
  // total amount of raising tokens that have already raised
  uint256 public totalAmount;
  // investor => amount of Tokens investor will get
  mapping (address => uint) public amount;
  // participators, unnecessary here
  //address[] public addressList;

  event Deposit(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 offeringAmount);
  event NewOffering(uint newStartBlock, uint newEndBlock, uint MGHAmount, uint raisingAmount);

  constructor (
      IERC20 _lpToken,
      IERC20 _offeringToken,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _offeringAmount,
      uint256 _raisingAmount
  ) public {
      adminAddress = msg.sender;            // admin is deployer
      lpToken = _lpToken;
      offeringToken = _offeringToken;
      startBlock = _startBlock;
      endBlock = _endBlock;
      offeringAmount = _offeringAmount;     // price set via offeringAmount / raisingAmount
      raisingAmount= _raisingAmount;
      totalAmount = 0;
      priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
  }

  modifier onlyAdmin() {
    require(msg.sender == adminAddress, "admin: wut?");
    _;
  }

  modifier IFOTime() {
    require(block.number > startBlock && block.number < endBlock, 'not ifo time');
    _;
  }

  // one function for deposits with lpToken and Ether
  function deposit(uint256 _amount) public payable IFOTime nonReentrant {
    require (lpToken.balanceOf(address(msg.sender)) >= _amount, 'you dont have enough USDT');   //check if investor has enough lpToken
    require (totalAmount.add(_amount) <= raisingAmount, 'not enough offering tokens left :(');  // depositing is only possible until raisingAmount is raised
    require (_amount > 0 || msg.value > 0, 'need _amount > 0');

   //lpToken.safeIncreaseAllowance(address(this), _amount);  // investor needs to approve before transferFrom
    lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
   //calculate amount of offering tokens user will get for _amount
    uint256 OTamount = _amount.mul(offeringAmount).div(raisingAmount);
    amount[msg.sender] = amount[msg.sender].add(OTamount);
    totalAmount = totalAmount.add(_amount);
    emit Deposit(msg.sender, _amount);

  }

  function harvest() public nonReentrant {
    require(block.number > endBlock, 'not harvest time yet');
    require (amount[msg.sender] > 0, 'have you participated?');

    uint256 HarvestAmount = amount[msg.sender];
    amount[msg.sender] = 0;                                            // maybe already sufficient reentrancy protection ?

    offeringToken.safeTransfer(address(msg.sender), HarvestAmount);
    emit Harvest(msg.sender, HarvestAmount);
  }
/*
    //calculate amount of tokens _user will get
  function getOfferingAmount(address _user) public view returns(uint256) {
    return amount[_user].mul(offeringAmount).div(raisingAmount);   
  }

  //check if someone has harvested; maybe restrict to harvest time
  function hasHarvest(address _user) external view HarvestTime returns(bool) {
   return amount[_user].claimed;
   }



 // view amount of investors
  function getAddressListLength() external view returns(uint256) {
    return addressList.length;
  }
 */

 //admin can withdraw LPToken/ether immediately (no funds for refund required)
  function WithdrawLiquidity(uint256 _lpAmount, uint WeiAmount, address payable _to) external onlyAdmin {
    lpToken.safeTransfer(address(msg.sender), _lpAmount);
    _to.transfer(WeiAmount);
  }

   // only possible ~2 weeks after Endblock => investors have a safe time to harvest
  function WithdrawOfferingToken(uint256 _offerAmount) external onlyAdmin {
    require( block.number > endBlock.add(1e5));
    require (_offerAmount <= offeringToken.balanceOf(address(this)), 'not enough offering token');
    offeringToken.safeTransfer(address(msg.sender), _offerAmount);
  }


    // Admin can announce new Offering ~2 weeks (100000 Blocks) after the last ended
  function NextRound(uint _offeringAmount, uint _raisingAmount, uint _startBlock, uint _endBlock) external onlyAdmin{
    // only possible ~2 weeks after Endblock => investors have a safe time to harvest
    require (block.number > endBlock.add(1e5), 'too early');
    startBlock = _startBlock;
    endBlock   = _endBlock;
    offeringAmount = _offeringAmount;
    raisingAmount = _raisingAmount;
    emit NewOffering(startBlock, endBlock, offeringAmount, raisingAmount);
  }
}