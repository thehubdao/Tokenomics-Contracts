# Locked Staking Rewards

## Important notes:
* The contract implements the receiveApproval() method to make deposits possible with only one transaction.<br>
  This method is available on the MGH token, but not part of the ERC20 standard.

## Time:<br>
### Cycle and Deposit Duration:<br>
The time management is dependent on **block.timestamp** and the variables cycleDuration and depositDuration are also denominated on seconds.<br>
Keep that in mind, when deploying the contract with a depositDuration, and when creating new Pools.<br>
>### Example:<br>
> depositDuration = 86400 => one day time span for deposits and withdraws<br>
> cycleDuration = 604800 => one week locking period for the pool

### startOfDeposit:<br>
The variable is a unix timestamp in seconds and defines the exact moment, at which deposits and withdraws from the pool will be enabled.<br>
Keep that in mind, when creating a new pool and setting the inital startOfDeposit.<br>
You can convert UNIX timestamps to dates and the other way around [here](https://www.epochconverter.com/).
>### Example:
> startOfDeposit = 1672531200 => deposits will open on the 01.01.2023.

## Calculating Rewards:
Important variables of the pool struct to calculate the rewards: tokenPerShareMultiplier<br>
The calculation of rewards is done by assigning each deposit an amount of shares and then multiplying the tokenPerShare property of the pool<br>
by the tokenPerShareMultiplier once during the locking Period. This makes compounding interest possible without any extra transactions. <br>
Since the EVM does not handle floating values, we use basis points to achieve acceptable precision when converting shares <=> tokens<br>
and when updating tokenPerShare.<br>
The initial tokenPerShare value must always be exactly 10000, which represents a 1 in basis points.<br>
The tokenPerShareMultiplier decimal value must be multiplied with 10000 to be used.<br>
>### Example:
> tokenPerShare = 10000 => 1 share is worth 1 token.<br>
> tokenPerShare = 20000 => 1 share is worth 2 tokens.<br>
> tokenPerShareMultiplier = 10000 => share value will not change<br>
> tokenPerShareMultiplier = 15000 => share value will increase by 50% <br>

relevant code snippets (basisPoints = 10000):<br>
updatePool():<br>
<code> tokenPerShare = tokenPerShare * tokenPerShareMultiplier / basisPoints </code><br>
sharesToToken(): <br>
<code> _sharesAmount * pool[_pool].tokenPerShare / basisPoints </code><br>
tokenToShares(): <br>
<code>_tokenAmount * basisPoints / pool[_pool].tokenPerShare</code>