pragma solidity 0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Ivesting.sol";
import "../IFO/IFixPrice.sol";


contract DACFactory {

  address public vestingImp;
  address public saleImp;
  address[] public vestingClones;
  address[] public saleClones;

  constructor(address vesting, address sale) {
    vestingImp = vesting;
    saleImp = sale;
  }

  function createVestingClone
    (
    address token,
    address admin,
    uint256 startInDays,
    uint256 durationInDays,
    uint256 cliff,
    uint256 cliffDelayInDays,
    uint256 exp
    )
    external returns(address clone)
    {
    clone = Clones.clone(vestingImp);
    Ivesting(clone).initialize(
      token,
      admin,
      startInDays,
      durationInDays,
      cliff,
      cliffDelayInDays,
      exp
    );
    vestingClones.push(clone);
  }

  function createSaleClone
    (
    address lpToken,
    address offeringToken,
    address priceFeed,
    address admin,
    uint256 offeringAmount,
    uint256 price,
    uint256 startBlock,
    uint256 endBlock,
    uint256 harvestBlock
    )
    external returns(address clone)
    {
    clone = Clones.clone(saleImp);
    IFixPrice(clone).initialize(
      lpToken,
      offeringToken,
      priceFeed,
      admin,
      offeringAmount,
      price,
      startBlock,
      endBlock,
      harvestBlock
    );
    saleClones.push(clone);
  }

  function customClone(address implementation) public returns(address clone) {
    clone = Clones.clone(implementation);
  }
}