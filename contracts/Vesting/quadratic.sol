pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/*
 This Contract allows for quadratic vesting of a single ERC20 token starting at a hardcoded Timestamp for a hardcoded duration.
 the amount of the balance a user can retrieve is linearly dependent on 
 the fraction of the duration that has already passed since startTime squared.
 => retrievableAmount = (timePassed/Duration)^2 * totalAmount
 => 50 percent of time passed => 25% of total amount is retrievable
 @dev this contract implements balanceOf function for implementation with the snapshot ERC20-balanceOf strategy
*/
contract QuadraticVesting is Ownable {

  IERC20 private token;
  uint256 public startTime;
  uint256 public duration;
  uint256 constant private dec = 10**0;     // @dev: fix decimals after testing
  mapping(address => uint256) public totalDeposit;
  mapping(address => uint256) private drainedAmount;

  constructor(IERC20 _token, uint256 _durationInDays, uint256 startInDays) {
    token = _token;
    startTime = block.timestamp + startInDays * 86400;
    duration = _durationInDays*86400;
  }

  function rawDeposit(address _from, address _for, uint256 _amount) internal {
    require(token.transferFrom(_from, address(this), _amount));
    totalDeposit[_for] += _amount;
  }

  function depositFor(address _recipient, uint256 _amount) public {
    rawDeposit(msg.sender, _recipient, _amount);
  }

  function depositAllFor(address _recipient) external {
    depositFor(_recipient, token.balanceOf(_recipient));
  }

  function retrieve() external {
    uint256 amount = _getRetrievableAmount(msg.sender);
    require(amount != 0, "nothing to retrieve");
    drainedAmount[msg.sender] += amount;
    token.transfer(msg.sender, amount);
    assert(drainedAmount[msg.sender] <= totalDeposit[msg.sender]);
  }

  function decreaseVesting(address _account, uint256 amount) external onlyOwner {
    require(drainedAmount[_account] <= totalDeposit[_account] - amount*dec, "deposit has to be >= drainedAmount");
    totalDeposit[_account] -= amount*dec;
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

  function _getRetrievableAmount(address _account) private view returns(uint256){
    return (_getPercentage() * totalDeposit[_account] / 1e4) - drainedAmount[_account];
  }

  function getRetrievableAmount() external view returns(uint256) {
    return _getRetrievableAmount(msg.sender)/dec;
  }

  function getTotalDeposit(address _account) external view returns(uint256){
    return totalDeposit[_account]/dec;
  }

  function getRetrievablePercentage() external view returns(uint256) {
    return _getPercentage() / 100;
  }

  function balanceOf(address account) external view returns(uint256) {
    return token.balanceOf(account) + totalDeposit[account] - drainedAmount[account];
  }
}