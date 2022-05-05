pragma solidity ^0.8.0;


contract mockAggregatorV3 {

  int256 immutable returnValue;

  constructor(int256 currenyValueCents) {
    returnValue = currenyValueCents * 10 ** 6;
  }  

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
  ) 
  {
      return (uint80(0), returnValue, 0, 0, uint80(0));
  }
}