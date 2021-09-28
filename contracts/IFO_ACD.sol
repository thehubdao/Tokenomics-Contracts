// SPDX-License-Identifier: MIT

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
// removed safeMath, see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/2465

pragma solidity "0.8.0";

// @title IFOV3

contract IFOACD is Ownable{
    using SafeERC20 for IERC20;

    // The LP token used
    IERC20 public lpToken;

    // The offering token
    IERC20 public offeringToken;

    // Number of pools
    uint8 private constant numberPools = 2;

    // The block number when IFO starts
    uint256 public startBlock;

    // The block number when IFO ends
    uint256 public endBlock;

    // Array of PoolCharacteristics of size numberPools
    PoolCharacteristics[numberPools] private _poolInformation;

    // maps the user-address and PoolID to the deposited amount in that Pool
    mapping(address => mapping(uint8 => uint256)) public amountPool;

    // Struct that contains each pool characteristics
    struct PoolCharacteristics {
        // amount of tokens offered for the pool (in offeringTokens)
        uint256 offeringAmountPool;
        // price in DIE/USDT => for 1 MGH/USDT price would be 10^12 
        // for Pool0 the price is set to priceA;
        // for Pool1 priceA is the lower bound (IN MGH/USDT) and priceB is irrelevant
        uint256 priceA;
        uint256 priceB;
        // total amount deposited in the Pool (in LP tokens); resets when new Start and EndBlock are set
        uint256 totalAmountPool;
    }

    // Admin withdraw events
    event AdminWithdraw(uint256 amountLP, uint256 amountOfferingToken, uint256 amountWei);

    // Admin recovers token
    event AdminTokenRecovery(address tokenAddress, uint256 amountTokens);

    // Deposit event
    event Deposit(address indexed user, uint256 amount, uint8 indexed pid);

    // Harvest event
    event Harvest(address indexed user, uint256 offeringAmount, uint8 indexed pid);

    // Event for new start & end blocks
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);

    // Event when parameters are set for one of the pools
    event PoolParametersSet(uint256 offeringAmountPool, uint priceA_, uint8 pid);

    // modifier to prevent admin from calling critical set up functions before 3 days after harvest time

    modifier adminTimeLock() {
        require(block.number >= endBlock + 21000, 'admin must wait');
        _;
    }


    /**
     * @dev It can only be called once.
     * @param _lpToken: the LP token used
     * @param _offeringToken: the token that is offered for the IFO
     */

    constructor(
        IERC20 _lpToken,
        IERC20 _offeringToken
    ) {
        require(_lpToken.totalSupply() >= 0);
        require(_offeringToken.totalSupply() >= 0);
        require(_lpToken != _offeringToken, "Tokens must be be different");
        lpToken = _lpToken;
        offeringToken = _offeringToken;
    }

    /**
     * @notice It allows users to deposit LP tokens to pool
     * @param _amount: the number of LP token used (6 decimals)
     * @param _pid: pool id
     */
    function depositPool(uint256 _amount, uint8 _pid) external {

        // Checks whether the pool id is valid
        require(_pid < numberPools, "Non valid pool id");

        // Checks that pool was set
        require(_poolInformation[_pid].offeringAmountPool > 0, "Pool not set");

        // Checks whether the block number is not too early
        require(block.number >= startBlock, "Too early");

        // Checks whether the block number is not too late
        require(block.number <= endBlock, "Too late");

        // Checks that the amount deposited is not inferior to 0
        require(_amount > 0, "Amount must be > 0");

        // if its pool1, check if new total amount will be smaller or equal to OfferingAmount / price
        if(_pid == 0){
          require(
            _poolInformation[_pid].offeringAmountPool >= (_poolInformation[_pid].totalAmountPool + (_amount)) * (_poolInformation[_pid].priceA),
            'not enough Offering Tokens left in Pool1');
        }

        // Transfers funds to this contract
        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        // Update the user status
        amountPool[msg.sender][_pid] += _amount;

        // Updates the totalAmount for pool
        _poolInformation[_pid].totalAmountPool += _amount;

        emit Deposit(msg.sender, _amount, _pid);
    }

    /**
     * @notice It allows users to harvest from pool
     * @notice if user is not whitelisted and the whitelist is active, the user is refunded in lpTokens
     * @param _pid: pool id
     */
    function harvestPool(uint8 _pid) external {
        // buffer time between end of deposit and start of harvest for admin to whitelist (~7 hours)
        require(block.number >= endBlock, "Too early");

        // Checks whether pool id is valid
        require(_pid < numberPools, "Non valid pool id");

        // Checks whether the user has participated
        require(amountPool[msg.sender][_pid] > 0, "Did not participate");

        uint256 offeringTokenAmount = _calculateOfferingAmountPool(
            msg.sender,
            _pid
        );

        amountPool[msg.sender][_pid] = 0;

        // Transfer these tokens back to the user
        offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
        emit Harvest(msg.sender, offeringTokenAmount, _pid);
    }


    /**
     * @notice It allows the admin to withdraw funds
     * @param _lpAmount: the number of LP token to withdraw (18 decimals)
     * @param _offerAmount: the number of offering amount to withdraw
     * @param _weiAmount: the amount of Wei to withdraw
     * @dev This function is only callable by admin.
     */
    function finalWithdraw(uint256 _lpAmount, uint256 _offerAmount, uint256 _weiAmount) external onlyOwner adminTimeLock  {

        if (_lpAmount > 0) {
            lpToken.safeTransfer(address(msg.sender), _lpAmount);
        }

        if (_offerAmount > 0) {
            offeringToken.safeTransfer(address(msg.sender), _offerAmount);
        }

        if (_weiAmount > 0){
            payable(address(msg.sender)).transfer(_weiAmount);
        }

        emit AdminWithdraw(_lpAmount, _offerAmount, _weiAmount);
    }

    function adminWithdraw() external onlyOwner {
        uint256 amount = lpToken.balanceOf(address(this));
        lpToken.transfer(msg.sender, amount);
        emit AdminWithdraw(amount, 0, 0);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw (18 decimals)
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(lpToken), "Cannot be LP token");
        require(_tokenAddress != address(offeringToken), "Cannot be offering token");

        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice It sets parameters for pool
     * @param _offeringAmountPool: offering amount (in tokens)
     * @param _pid: pool id
     * @dev This function is only callable by admin.
     * @notice can not offer more than the current balance of the contract
     * @notice 
     */
    function setPool(
        uint256 _offeringAmountPool,
        uint256 _priceA,
        uint8 _pid
    ) external  onlyOwner adminTimeLock {

        require(_pid < numberPools, "Pool does not exist");

        _poolInformation[_pid].offeringAmountPool = _offeringAmountPool;
        _poolInformation[_pid].priceA = _priceA;

        //calculate the current total OfferingAmount
        uint sum = 0;
        for (uint j = 0; j < numberPools; j++){
            sum += _poolInformation[j].offeringAmountPool;
        }
        //require that all offered tokens are in the contract
        require(sum <= offeringToken.balanceOf(address(this)),
        'cant offer more than balance');

        emit PoolParametersSet(_offeringAmountPool, _priceA, _pid);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @param _startBlock: the new start block
     * @param _endBlock: the new end block
     * @notice 
     * @notice automatically resets the totalAmount in each Pool to 0
     */
    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _endBlock) external onlyOwner adminTimeLock  {
        require(_startBlock < _endBlock, "New startBlock must be lower than new endBlock");
        require(block.number < _startBlock, "New startBlock must be higher than current block");
      //reset the totalAmount in each pool, when initiating new start and end blocks
        for(uint j = 0; j < numberPools; j++){
            _poolInformation[j].totalAmountPool = 0;
        }
        startBlock = _startBlock;
        endBlock = _endBlock;

        emit NewStartAndEndBlocks(_startBlock, _endBlock);
    }

    /**
     * @notice It returns the pool information
     * @param _pid: poolId
     * @return offeringAmountPool: amount of tokens offered for the pool (in offeringTokens)
     * @return totalAmountPool: total amount pool deposited (in LP tokens)
     */
    function viewPoolInformation(uint256 _pid)
        external
        view
        
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            _poolInformation[_pid].offeringAmountPool,
            _poolInformation[_pid].priceA,
            _poolInformation[_pid].priceB,
            _poolInformation[_pid].totalAmountPool
        );
    }

    /**
     * @notice External view function to see user allocations
     * @param _user: user address
     * @param _pids[]: array of pids
     * @return
     */
    function viewUserAllocationPools(address _user, uint8[] calldata _pids)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory allocationPools = new uint256[](_pids.length);
        for (uint8 i = 0; i < _pids.length; i++) {
            allocationPools[i] = _getUserAllocationPool(_user, _pids[i]);
        }
        return allocationPools;
    }

    /**
     * @notice External view function to see user amount in pools
     * @param _user: user address
     * @param _pids[]: array of pids
     */
    function viewUserAmount(address _user, uint8[] calldata _pids)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory amountPools = new uint256[](_pids.length);

        for (uint8 i = 0; i < numberPools; i++) {
            amountPools[i] = amountPool[_user][i];
        }
        return (amountPools);
    }

    /**
     * @notice External view function to see user offering and refunding amounts 
     * @param _user: user address
     * @param _pids: array of pids
     */
    function viewUserOfferingAmountsForPools(address _user, uint8[] calldata _pids)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory amountPools = new uint256[](_pids.length);

        for (uint8 i = 0; i < _pids.length; i++) {
          uint256 userOfferingAmountPool;

          if (_poolInformation[_pids[i]].offeringAmountPool > 0) {
            userOfferingAmountPool = _calculateOfferingAmountPool(_user, _pids[i]);
          }

          amountPools[i] = userOfferingAmountPool;
        }
        return amountPools;
    }

    /**
     * @notice It calculates the offering amount for a user and the number of LP tokens to transfer back.
     * @param _user: user address
     * @param _pid: pool id
     * @return {uint256, uint256} It returns the offering amount, the refunding amount (in LP tokens)
     */
    function _calculateOfferingAmountPool(address _user, uint8 _pid)
      internal
      view
      returns (uint256)
    {
      if(amountPool[_user][_pid] == 0){
        return(0);
      }

		uint256 userOfferingAmount;
      // calculate for Pool1
      if (_pid == 0){
        userOfferingAmount = amountPool[_user][0] * (_poolInformation[0].priceA);
        return userOfferingAmount;
      }

      // calculate for Pool2
      if (_pid == 1){
        if(_poolInformation[1].offeringAmountPool / _poolInformation[1].totalAmountPool > _poolInformation[1].priceA){
          return amountPool[_user][1] * (_poolInformation[0].priceA);
        }else{
          return _getUserAllocationPool(_user, _pid) * _poolInformation[1].offeringAmountPool / 1e12;
        }
      }
    }

    /**
     * @notice It returns the user allocation for pool
     * @dev 100,000,000,000 means 0.1 (10%) / 1 means 0.0000000000001 (0.0000001%) / 1,000,000,000,000 means 1 (100%)
     * @param _user: user address
     * @param _pid: pool id
     * @return it returns the user's share of pool
     */
    function _getUserAllocationPool(address _user, uint8 _pid) internal view returns (uint256) {
        if (_poolInformation[_pid].totalAmountPool > 0) {
            return amountPool[_user][_pid] * (1e12) / _poolInformation[_pid].totalAmountPool;
        } else {
            return 0;
        }
    }
}
