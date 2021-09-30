pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*
 This Contract allows for quadratic vesting of a single ERC20 token starting at a hardcoded Timestamp for a hardcoded duration.
 the amount of the balance a user can retrieve is linearly dependent on 
 the fraction of the duration that has already passed since startTime squared.
 => retrievableAmount = (timePassed/Duration)^2 * totalAmount
 => 50 percent of time passed => 25% of total amount is retrievable
*/
contract QuadraticVesting {

  IERC20 private token;
  uint256 public startTime;
  uint256 public duration;
  uint256 constant private dec = 10**0;     // @dev: fix decimals after testing
  mapping(address => uint256) private totalDeposit;
  mapping(address => uint256) private drainedAmount;

  constructor(IERC20 _token, uint256 _durationInDays, uint256 startInDays) {
    token = _token;
    startTime = block.timestamp + startInDays * 86400;
    duration = _durationInDays*86400;
  }

  function depositFor(address _recipient, uint256 _amount) external {
    require(token.transferFrom(msg.sender, address(this), _amount*dec), "transfer failed, approve first!");
    totalDeposit[_recipient] += _amount*dec;
  }

  function retrieve() external {
    uint256 amount = _getRetrievableAmount(msg.sender);
    require(amount != 0, "nothing to retrieve");
    drainedAmount[msg.sender] += amount;
    token.transfer(msg.sender, amount);
    assert(drainedAmount[msg.sender] <= totalDeposit[msg.sender]);
  }

    // 1e8 => 100%; 1e7 => 10%; 1e6 => 1%;
    // if startTime is not reached return 0
    // if the duration is over return 1e10
  function _getPercentage() private view returns(uint256) {
    if(startTime > block.timestamp){
      return 0;
    }else if(startTime + duration > block.timestamp){
      return ((1e2 * (block.timestamp - startTime))**2 / duration**2);
    }else{
      return 1e4;
    }
  }

  function _getRetrievableAmount(address _account) internal view returns(uint256){
    return (_getPercentage() * totalDeposit[_account] / 1e4) - drainedAmount[_account];
  }

  function getRetrievableAmount(address _account) external view returns(uint256) {
    return _getRetrievableAmount(_account)/dec;
  }

  function getTotalBalance(address _account) external view returns(uint256){
    return (totalDeposit[_account] - drainedAmount[_account])/dec;
  }

  function getRetrievablePercentage() external view returns(uint256) {
    return _getPercentage() / 100;
  }
}