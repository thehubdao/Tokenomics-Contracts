Welcome to the repository containing the contracts for managing Tokenomics for any project!

  This repo contains contracts for:
    1. Token distribution
    2. Vesting
    3. Staking (in progress)
    4. A factory contract to facilitate cheap, immutable replicas
   --more documentation can be found in the contracts
   
1. Token distribution - FixPrice.sol

    1.1 What can this contract do?
    
      This contract is designed as a monolith to distribute ERC20 Tokens with 18 decimals for ERC20 Tokens with 6 decimals or for ETH.
      Depositing is only possible until all the offered tokens are sold, that is until the totalAmount (deposited) is equal to the offeredAmount * price.
      E.g. you can distribute your own ERC20 with 18 decimals for one of the prominent stable coins with 6 decimals like USDc, USDT etc.
      For ether payments it implements a Chainlink pricefeed that returns the ETH/USD price with 8 decimal places.
      
    1.2 Specifications
    
      When initializing an instance of this contract you can specify the token to be distributed as well as the token of payment.
      You can specify a pricefeed to be used for ether payments.
      You must specify a startBlock, endBlock and harvestBlock. Deposits can be made between startBlock and endBlock. Harvesting is possible after harvestBlock.
      You must specify an owner address, the owner can access special functions:
        - Withdraw funds from the contract.
        - Udate the amount to be offered, the price and the startBlock, endBlock and harvestBlock.
          Critical actions like changing the price and blocks are only callable a certain amount of Blocks after HarvestBlock, so that users can safely harvest
          their tokens before a breaking change hits the contract.
          
    1.3 Bottlenecks
    
      Before depositing and ERC20 token via calling deposit() the user has to set an approval for the sale Contract on the ERC20 token contract
      by calling IERC20(token).approve(saleContract, amount).
      You have to fund the sale contract with the offeringToken, so that users can harvest() successfully.
      The mapping(user => amount) only gets reset to 0 for user if harvest was called successfully. That means that users who do not harvest keep their deposited balance
      for the next round in case the contract is reused.
     
      
      
