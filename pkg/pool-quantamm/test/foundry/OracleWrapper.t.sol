// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/mock/MockChainlinkOracles.sol";

contract OracleWrapperTest is Test {
    MockChainlinkOracle internal chainlinkOracle;

    // Helper function to deploy the oracle
    function deployOracle(int216 fixedValue, uint delay) internal returns (MockChainlinkOracle) {
        return new MockChainlinkOracle(fixedValue, delay);
    }

    // Test 1: Should return fresh information of primary oracle
    function testShouldReturnFreshInformationOfPrimaryOracle() public {
        int216 fixedValue = 1000; // Same as ethers.utils.parseEther("1000") in JS
        uint delay = 3600;

        // Deploy the oracle
        chainlinkOracle = deployOracle(fixedValue, delay);

        // Warp the block time to simulate the time delay
        vm.warp(block.timestamp + delay);

        // Get data from the oracle
        (int216 data, uint40 timestamp) = chainlinkOracle.getData();

        // Check the values
        assertEq(data, fixedValue); // Check if data equals 1000 ether

        uint256 nowTimestamp = block.timestamp;
        assertEq(timestamp, nowTimestamp - delay); // Check if timestamp is correct
    }

    // Test 2: Should return stale information of primary oracle
    function testShouldReturnStaleInformationOfPrimaryOracle() public {
        int216 fixedValue = 1000; // Same as ethers.utils.parseEther("1000") in JS
        uint delay = 3600 * 5; // 5 hours delay

        // Deploy the oracle
        chainlinkOracle = deployOracle(fixedValue, delay);

        // Warp the block time to simulate the time delay
        vm.warp(block.timestamp + delay);

        // Get data from the oracle
        (int216 data, uint40 timestamp) = chainlinkOracle.getData();

        // Check the values
        assertEq(data, fixedValue); // Check if data equals 1000 ether

        uint256 nowTimestamp = block.timestamp;
        assertEq(timestamp, nowTimestamp - delay); // Check if timestamp is correct
    }
}
