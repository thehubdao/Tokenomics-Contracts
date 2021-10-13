pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../ProxyClones/OwnableForClones.sol";

/*
 This Contract allows for vesting of a single ERC20 token starting at a hardcoded Timestamp for a hardcoded duration.
 the amount of the balance a user can retrieve is linearly dependent on
 the fraction of the duration that has already passed since startTime squared.
 => retrievableAmount = (timePassed/Duration)^2 * totalAmount
 => 50 percent of time passed => 25% of total amount is retrievable
 @dev this contract implements balanceOf function for implementation with the snapshot ERC20-balanceOf strategy
*/


contract Vesting is OwnableForClones {

  IERC20 private token;
  uint256 public startTime;
  uint256 public duration;
  uint256 private exp;
  // cliff: 100 = 1%;
  uint256 private cliff;
  uint256 private cliffDelay;
  mapping(address => uint256) private totalDeposit;
  mapping(address => uint256) private drainedAmount;

  function initialize
   (
    address _token,
    address _owner,
    uint256 _startInDays,
    uint256 _durationInDays,
    uint256 _cliffInTenThousands,
    uint256 _cliffDelayInDays,
    uint256 _exp
   )
    external initializer
   {
    __Ownable_init();
    token = IERC20(_token);
    startTime = block.timestamp + _startInDays * 86400;
    duration = _durationInDays * 86400;
    cliff = _cliffInTenThousands;
    cliffDelay = _cliffDelayInDays * 86400;
    exp = _exp;
    if (_owner == address(0)) {
      renounceOwnership();
    }else {
      transferOwnership(_owner);
    }
  }

  function depositAllFor(address _recipient) external {
    depositFor(_recipient, token.balanceOf(_recipient));
  }

  function retrieve() external {
    uint256 amount = getRetrievableAmount(msg.sender);
    require(amount != 0, "nothing to retrieve");
    _rawRetrieve(msg.sender, amount);
  }

  function retrieveFor(address[] memory accounts) external {
    for (uint256 i = 0; i < accounts.length; i++) {
      uint256 amount = getRetrievableAmount(accounts[i]);
      _rawRetrieve(accounts[i], amount);
    }
  }

  function decreaseVesting(address _account, uint256 amount) external onlyOwner {
    require(drainedAmount[_account] <= totalDeposit[_account] - amount, "deposit has to be >= drainedAmount");
    totalDeposit[_account] -= amount;
  }

  function getTotalDeposit(address _account) external view returns(uint256) {
    return totalDeposit[_account];
  }

  function getRetrievablePercentage() external view returns(uint256) {
    return _getPercentage() / 100;
  }

  function balanceOf(address account) external view returns(uint256) {
    return token.balanceOf(account) + totalDeposit[account] - drainedAmount[account];
  }

  function getRetrievableAmount(address _account) public view returns(uint256) {
    return (_getPercentage() * totalDeposit[_account] / 1e4) - drainedAmount[_account];
  }

  function depositFor(address _recipient, uint256 _amount) public {
    _rawDeposit(msg.sender, _recipient, _amount);
  }

  function _rawDeposit(address _from, address _for, uint256 _amount) internal {
    require(token.transferFrom(_from, address(this), _amount));
    totalDeposit[_for] += _amount;
  }

  function _rawRetrieve(address account, uint256 amount) internal {
    drainedAmount[account] += amount;
    token.transfer(account, amount);
    assert(drainedAmount[account] <= totalDeposit[account]);
  }

    // 1e4 => 100%; 1e3 => 10%; 1e2 => 1%;
    // if startTime is not reached return 0
    // if the duration is over return 1e4
  function _getPercentage() private view returns(uint256) {
    if (cliff == 0) {
      return _getPercentageNoCliff();
    }else {
      return _getPercentageWithCliff();
    }
  }

  function _getPercentageNoCliff() private view returns(uint256) {
    if (startTime > block.timestamp) {
      return 0;
    }else if (startTime + duration > block.timestamp) {
      return 1e4 * (block.timestamp - startTime)**exp / duration**exp;
    }else {
      return 1e4;
    }
  }

  function _getPercentageWithCliff() private view returns(uint256) {
    if (block.timestamp + cliffDelay < startTime) {
      return 0;
    }else if (block.timestamp < startTime) {
      return cliff;
    }else if (1e4 * (block.timestamp - startTime)**exp / duration**exp + cliff < 1e4) {
      return (1e4 * (block.timestamp - startTime)**exp / duration**exp) + cliff;
    }else {
      return 1e4;
    }
  }

}