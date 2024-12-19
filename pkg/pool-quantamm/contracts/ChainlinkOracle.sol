// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;


import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";

/// @title ChainlinkOracle contract based on the underlying QuantAMM oracle wrapper
/// @notice Contains the logic for retrieving data from a Chainlink oracle and converting it to the QuantAMM format using the oracle wrapper contract 
contract ChainlinkOracle is OracleWrapper {
    AggregatorV3Interface internal immutable priceFeed;

    ///@notice Difference of feed result to 18 decimals. We store the difference instead of the oracle decimals for optimization reasons (saves a subtraction in _getData)
    uint internal immutable normalizationFactor;

    /// @param _chainlinkFeed the address of the Chainlink oracle to wrap  
    constructor(address _chainlinkFeed) {
        require(_chainlinkFeed != address(0), "INVADDR"); //Invalid address provided
        priceFeed = AggregatorV3Interface(_chainlinkFeed);
        // Chainlink oracles have <= 18 decimals, cannot underflow
        normalizationFactor = 18 - priceFeed.decimals();
    }

    /// @notice Returns the latest data from the oracle in the QuantAMM format
    /// @return data the latest data from the oracle in the QuantAMM format
    /// @return timestamp the timestamp of the data retrieval 
    function _getData() internal view override returns (int216, uint40) {
        (, /*uint80 roundID*/ int data, , /*uint startedAt*/ uint timestamp, ) = /*uint80 answeredInRound*/
        priceFeed.latestRoundData();
        require(data > 0, "INVLDDATA");
        data = data * int(10 ** normalizationFactor);
        return (int216(data), uint40(timestamp)); // Overflow of data is extremely improbable and uint40 is large enough for timestamps for a very long time
    }
}
