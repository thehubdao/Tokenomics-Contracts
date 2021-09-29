pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*
 This Contract allows for linear vesting of a single ERC20 token starting at a hardcoded Timestamp for a hardcoded duration.
 the amount of the balance a user can retrieve is linearly dependent on 
 the fraction of the duration that has already passed since startTime.
*/
contract VestingWallet {

  IERC20 constant private token = IERC20(address(0));
  uint256 public startTime;
  uint256 public duration;
  uint256 constant private dec = 10**18;
  mapping(address => uint256) private totalDeposit;
  mapping(address => uint256) private drainedAmount;

  constructor(uint256 _durationInDays, uint256 startInDays) {
    startTime = block.timestamp + startInDays * 86400;
    duration = _durationInDays*86400;
  }

  function depositFor(uint256 _amount, address _recipient) external {
    require(token.transferFrom(msg.sender, address(this), _amount*dec), "transfer failed");
    totalDeposit[_recipient] += _amount*dec;
  }

  function retrieve() external {
    uint256 amount = getRetrievableAmount(msg.sender);
    drainedAmount[msg.sender] += amount;
    token.transfer(msg.sender, amount);
    assert(drainedAmount[msg.sender] < totalDeposit[msg.sender]);
  }

    // 1e10 => 100%; 1e9 => 10%; 1e8 => 1%;
    // if startTime is not reached return 0
    // if the duration is over return 1e10
  function getPercentage() private view returns(uint256 percentage) {
    if(block.timestamp < startTime){
        percentage = 0;
    }else if(startTime + duration > block.timestamp){
      percentage = 1e10 * (block.timestamp - startTime) / duration;
    }else{
      percentage = 1e10;
    }
  }

  function getRetrievableAmount(address _account) public view returns(uint256){
    return (getPercentage() * totalDeposit[_account] / 1e10) - drainedAmount[_account];
  }

  function getTotalBalance(address _account) external view returns(uint256){
    return (totalDeposit[_account] - drainedAmount[_account])/dec;
  }
}