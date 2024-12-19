// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/mock/MockChainlinkOracles.sol";
import "../../contracts/MultiHopOracle.sol";

contract MultiHopOracleTest is Test {
    MockChainlinkOracle internal chainlinkOracle1;
    MockChainlinkOracle internal chainlinkOracle2;
    MultiHopOracle internal multiHopOracle;

    // Helper function to deploy the oracles
    function deployOracles(
        int216 fixedValue1,
        int216 fixedValue2,
        uint delay1,
        uint delay2,
        bool[] memory invert
    ) internal returns (MultiHopOracle) {
        chainlinkOracle1 = new MockChainlinkOracle(fixedValue1, delay1);
        chainlinkOracle2 = new MockChainlinkOracle(fixedValue2, delay2);

        address[] memory oracles = new address[](2);
        oracles[0] = address(chainlinkOracle1);
        oracles[1] = address(chainlinkOracle2);
        bool[] memory invertFlags = new bool[](2);
        invertFlags[0] = invert[0];
        invertFlags[1] = invert[1];

        MultiHopOracle.HopConfig[] memory hops = new MultiHopOracle.HopConfig[](2);
        hops[0] = MultiHopOracle.HopConfig({ oracle: OracleWrapper(address(chainlinkOracle1)), invert: invert[0] });
        hops[1] = MultiHopOracle.HopConfig({ oracle: OracleWrapper(address(chainlinkOracle2)), invert: invert[1] });

        multiHopOracle = new MultiHopOracle(hops);
        return multiHopOracle;
    }

    // Test 1: Without inversion
    function testShouldReturnMultipliedDataWithoutInversion() public {
        int216 fixedValue1 = 1000;
        int216 fixedValue2 = 0.001e18;
        uint delay1 = 3600;
        uint delay2 = 3600;

        bool[] memory invert = new bool[](2);
        invert[0] = false;
        invert[1] = false;

        multiHopOracle = deployOracles(fixedValue1, fixedValue2, delay1, delay2, invert);

        // Simulate time
        vm.warp(block.timestamp + 3600);

        (int216 data, uint40 timestamp) = multiHopOracle.getData();
        uint40 nowTimestamp = uint40(block.timestamp);

        assertEq(timestamp, nowTimestamp - delay1);
        assertEq(data, 1); // 1000 * 0.001 = 1
    }

    // Test 2: With second oracle inverted
    function testShouldReturnMultipliedDataWithSecondInverted() public {
        int216 fixedValue1 = 10e18; //this tests the invert conversion
        int216 fixedValue2 = 100;
        uint delay1 = 3600;
        uint delay2 = 3600;

        bool[] memory invert = new bool[](2);
        invert[0] = true;
        invert[1] = false;

        multiHopOracle = deployOracles(fixedValue1, fixedValue2, delay1, delay2, invert);

        // Simulate time
        vm.warp(block.timestamp + 3600);

        (int216 data, uint40 timestamp) = multiHopOracle.getData();
        uint40 nowTimestamp = uint40(block.timestamp);

        assertEq(timestamp, nowTimestamp - delay1);
        assertEq(data, 10); // 1000 / 100 = 10
    }

    // Test 3: With first oracle inverted
    function testShouldReturnMultipliedDataWithFirstInverted() public {
        int216 fixedValue1 = 1000;
        int216 fixedValue2 = 10e18;
        uint delay1 = 3600;
        uint delay2 = 3600;

        bool[] memory invert = new bool[](2);
        invert[0] = false;
        invert[1] = true;

        multiHopOracle = deployOracles(fixedValue1, fixedValue2, delay1, delay2, invert);

        // Simulate time
        vm.warp(block.timestamp + 3600);

        (int216 data, uint40 timestamp) = multiHopOracle.getData();
        uint40 nowTimestamp = uint40(block.timestamp);

        assertEq(timestamp, nowTimestamp - delay1);
        assertEq(data, 100); // 1000 / 10 = 100
    }

    // Test 4: Should return lower timestamp (the second delay is greater)
    function testShouldReturnLowerTimestamp() public {
        int216 fixedValue1 = 1000;
        int216 fixedValue2 = 0.001e18;
        uint delay1 = 3600;
        uint delay2 = 3650;

        bool[] memory invert = new bool[](2);
        invert[0] = false;
        invert[1] = false;

        multiHopOracle = deployOracles(fixedValue1, fixedValue2, delay1, delay2, invert);

        // Simulate time
        vm.warp(block.timestamp + 3650);

        (int216 data, uint40 timestamp) = multiHopOracle.getData();
        uint40 nowTimestamp = uint40(block.timestamp);

        assertEq(timestamp, nowTimestamp - delay2);
        assertEq(data, 1); // 1000 * 0.001 = 1
    }
}
