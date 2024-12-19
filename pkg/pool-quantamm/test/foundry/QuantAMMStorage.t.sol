// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../contracts/mock/MockQuantAMMStorage.sol"; // Assuming your MockQuantAMMStorage contract is in the src folder
import { QuantAMMTestUtils } from "./utils.t.sol";

contract QuantAMMStorageTest is Test, QuantAMMTestUtils {
    MockQuantAMMStorage internal mockQuantAMMStorage;

    // Deploy MockQuantAMMStorage contract before each test
    function setUp() public {
        mockQuantAMMStorage = new MockQuantAMMStorage();
    }

    // Helper function to check array contents
    function ArrayCheckSum(int128[] memory sourceArray, int128[] memory targetArray) internal pure {
        // Ensure both arrays are of the same length
        assertEq(targetArray.length, sourceArray.length);

        // Compare each element in the arrays
        for (uint256 i = 0; i < sourceArray.length; i++) {
            assertEq(targetArray[i], sourceArray[i]);
        }
    }

    function testOverFlowCheckForPack32(int256 val, uint256 arrayLength) public {
        uint256 boundArrayLength = bound(arrayLength, 1, 16);
        int256 boundOverMax32 = bound(val, int256(type(int32).max) * 1e10, (int256(type(int32).max)) * 1e18);
        int256[] memory targetValues = new int256[](boundArrayLength);
        for (uint256 i = 0; i < boundArrayLength; i++) {
            targetValues[i] = 1e9;
        }

        for(uint256 i = 0; i < boundArrayLength; i++) {
            targetValues[i] = boundOverMax32;
            vm.expectRevert("Overflow");
            mockQuantAMMStorage.ExternalQuantAMMPack32Array(targetValues);
            targetValues[i] = 1e9;
        }
    }

    function testUnderFlowCheckForPack32(int256 val, uint256 arrayLength) public {
        uint256 boundArrayLength = bound(arrayLength, 1, 16);
        int256 boundUnder32 = bound(val, int256(type(int32).min) * 1e27, int256(type(int32).min) * 1e18 - 1);
        int256[] memory targetValues = new int256[](boundArrayLength);
        for (uint256 i = 0; i < boundArrayLength; i++) {
            targetValues[i] = 1e9;
        }

        for(uint256 i = 0; i < boundArrayLength; i++) {
            targetValues[i] = boundUnder32;
            vm.expectRevert("Overflow");
            mockQuantAMMStorage.ExternalQuantAMMPack32Array(targetValues);
            targetValues[i] = 1e9;
        }
    }

    function testMaxMinCheckForPack32(uint256 arrayLength) public view {
        uint256 boundArrayLength = bound(arrayLength, 1, 16);
        int256[] memory targetValues = new int256[](boundArrayLength);
        for (uint256 i = 0; i < boundArrayLength; i++) {
            targetValues[i] = 1e9;
        }

        for(uint256 i = 0; i < boundArrayLength; i++) {
            targetValues[i] = type(int32).max;
            mockQuantAMMStorage.ExternalQuantAMMPack32Array(targetValues);

            targetValues[i] = type(int32).min;
            mockQuantAMMStorage.ExternalQuantAMMPack32Array(targetValues);

            targetValues[i] = 1e9;
        }
    }

    // Test 1: Encoding and Decoding of 128-bit Arrays (Smallest Array)
    function testSmallestArray() public view {
        // Define the target values
        int256[] memory targetValues = new int256[](2);
        targetValues[0] = 4e18;
        targetValues[1] = 5e18;

        // Call the ExternalEncodeDecode128Array function from the contract
        int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode128Array(targetValues, 2);

        checkResult(redecoded, targetValues);
    }
    // Test 2: Encoding and Decoding of 128-bit Arrays (Smallest Odd Array)
    function testSmallestOddArray() public view {
        // Define the target values
        int256[] memory targetValues = new int256[](3);
        targetValues[0] = 4e18;
        targetValues[1] = 5e18;
        targetValues[2] = 6e18;

        // Call the ExternalEncodeDecode128Array function from the contract
        int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode128Array(targetValues, 3);

        checkResult(redecoded, targetValues);
    }

    // Test 3: Encoding and Decoding of 128-bit Arrays (Large Odd Array)
    function testLargeOddArray() public view {
        // Define the target values
        int256[] memory targetValues = new int256[](11);
        targetValues[0] = 1e18;
        targetValues[1] = 2e18;
        targetValues[2] = 3e18;
        targetValues[3] = 4e18;
        targetValues[4] = 5e18;
        targetValues[5] = 6e18;
        targetValues[6] = 7e18;
        targetValues[7] = 8e18;
        targetValues[8] = 9e18;
        targetValues[9] = 10e18;
        targetValues[10] = 11e18;

        // Call the ExternalEncodeDecode128Array function from the contract
        int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode128Array(targetValues, 11);

        checkResult(redecoded, targetValues);
    }

    // Test 4: Encoding and Decoding of 128-bit Arrays (Large Even Array)
    function testLargeEvenArray() public view {
        // Define the target values
        int256[] memory targetValues = new int256[](12);
        targetValues[0] = 1e18;
        targetValues[1] = 2e18;
        targetValues[2] = 3e18;
        targetValues[3] = 4e18;
        targetValues[4] = 5e18;
        targetValues[5] = 6e18;
        targetValues[6] = 7e18;
        targetValues[7] = 8e18;
        targetValues[8] = 9e18;
        targetValues[9] = 10e18;
        targetValues[10] = 11e18;
        targetValues[11] = 12e18;

        // Call the ExternalEncodeDecode128Array function from the contract
        int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode128Array(targetValues, 12);

        checkResult(redecoded, targetValues);
    }
    // Test: Precision test for encoding and decoding arrays
    function testPrecision() public view {
        // Define the target values with high precision
        int256[] memory targetValuesPrecision = new int256[](24);
        targetValuesPrecision[0] = 111111111111111111e18 + 1;
        targetValuesPrecision[1] = 211111111111111111e18 + 2;
        targetValuesPrecision[2] = 311111111111111111e18 + 3;
        targetValuesPrecision[3] = 411111111111111111e18 + 4;
        targetValuesPrecision[4] = 511111111111111111e18 + 5;
        targetValuesPrecision[5] = 611111111111111111e18 + 6;
        targetValuesPrecision[6] = 711111111111111111e18 + 7;
        targetValuesPrecision[7] = 811111111111111111e18 + 8;
        targetValuesPrecision[8] = 911111111111111111e18 + 9;
        targetValuesPrecision[9] = 111111111111111111e18 + 12;
        targetValuesPrecision[10] = 211111111111111111e18 + 13;
        targetValuesPrecision[11] = 211111111111111111e18 + 14;
        targetValuesPrecision[12] = 311111111111111111e18 + 15;
        targetValuesPrecision[13] = 411111111111111111e18 + 16;
        targetValuesPrecision[14] = 511111111111111111e18 + 17;
        targetValuesPrecision[15] = 611111111111111111e18 + 18;
        targetValuesPrecision[16] = 711111111111111111e18 + 21;
        targetValuesPrecision[17] = 811111111111111111e18 + 22;
        targetValuesPrecision[18] = 911111111111111111e18 + 23;
        targetValuesPrecision[19] = 111111111111111111e18 + 24;
        targetValuesPrecision[20] = 211111111111111111e18 + 25;
        targetValuesPrecision[21] = 311111111111111111e18 + 26;
        targetValuesPrecision[22] = 411111111111111111e18 + 27;
        targetValuesPrecision[23] = 511111111111111111e18 + 28;

        int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode128Array(
            targetValuesPrecision,
            targetValuesPrecision.length
        );

        checkResult(redecoded, targetValuesPrecision);
    }

    // Test 1: Encoding and Decoding of 32-bit Arrays (Basic Values)
    function testBasicArray() public view {
        // Define the basic target values
        int256[] memory targetValuesBasic = new int256[](24);
        targetValuesBasic[0] = 0.1e18; // 0.1
        targetValuesBasic[1] = 0.2e18; // 0.2
        targetValuesBasic[2] = 0.3e18; // 0.3
        targetValuesBasic[3] = 0.4e18; // 0.4
        targetValuesBasic[4] = 0.5e18; // 0.5
        targetValuesBasic[5] = 0.6e18; // 0.6
        targetValuesBasic[6] = 0.7e18; // 0.7
        targetValuesBasic[7] = 0.8e18; // 0.8
        targetValuesBasic[8] = 0.9e18; // 0.9
        targetValuesBasic[9] = 0.12e18; // 0.12
        targetValuesBasic[10] = 0.13e18; // 0.13
        targetValuesBasic[11] = 0.14e18; // 0.14
        targetValuesBasic[12] = 0.15e18; // 0.15
        targetValuesBasic[13] = 0.16e18; // 0.16
        targetValuesBasic[14] = 0.17e18; // 0.17
        targetValuesBasic[15] = 0.18e18; // 0.18
        targetValuesBasic[16] = 0.21e18; // 0.21
        targetValuesBasic[17] = 0.22e18; // 0.22
        targetValuesBasic[18] = 0.23e18; // 0.23
        targetValuesBasic[19] = 0.24e18; // 0.24
        targetValuesBasic[20] = 0.25e18; // 0.25
        targetValuesBasic[21] = 0.26e18; // 0.26
        targetValuesBasic[22] = 0.27e18; // 0.27
        targetValuesBasic[23] = 0.28e18; // 0.28

        // Perform encoding and decoding test for each sliced array (from 2 to full length)
        for (uint256 i = 2; i <= targetValuesBasic.length; i++) {
            // Create the test target values array by slicing the original array
            int256[] memory testTargetValues = new int256[](i);
            for (uint256 j = 0; j < i; j++) {
                testTargetValues[j] = targetValuesBasic[targetValuesBasic.length - i + j];
            }

            // Call the ExternalEncodeDecode32Array function from the contract
            int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode32Array(
                testTargetValues,
                testTargetValues.length
            );

            // Check if the original and decoded arrays are the same
            checkResult(redecoded, testTargetValues);
        }
    }

    // Test 2: Encoding and Decoding of 32-bit Arrays (High Precision Values)
    function testPrecisionArray() public view {
        // Define the precision target values
        int256[] memory targetValuesPrecision = new int256[](24);
        targetValuesPrecision[0] = 0.000000001e18; // 0.000000001
        targetValuesPrecision[1] = 0.000000002e18; // 0.000000002
        targetValuesPrecision[2] = 0.000000003e18; // 0.000000003
        targetValuesPrecision[3] = 0.000000004e18; // 0.000000004
        targetValuesPrecision[4] = 0.000000005e18; // 0.000000005
        targetValuesPrecision[5] = 0.000000006e18; // 0.000000006
        targetValuesPrecision[6] = 0.000000007e18; // 0.000000007
        targetValuesPrecision[7] = 0.000000008e18; // 0.000000008
        targetValuesPrecision[8] = 0.000000009e18; // 0.000000009
        targetValuesPrecision[9] = 0.000000012e18; // 0.000000012
        targetValuesPrecision[10] = 0.000000013e18; // 0.000000013
        targetValuesPrecision[11] = 0.000000014e18; // 0.000000014
        targetValuesPrecision[12] = 0.000000015e18; // 0.000000015
        targetValuesPrecision[13] = 0.000000016e18; // 0.000000016
        targetValuesPrecision[14] = 0.000000017e18; // 0.000000017
        targetValuesPrecision[15] = 0.000000018e18; // 0.000000018
        targetValuesPrecision[16] = 0.000000021e18; // 0.000000021
        targetValuesPrecision[17] = 0.000000022e18; // 0.000000022
        targetValuesPrecision[18] = 0.000000023e18; // 0.000000023
        targetValuesPrecision[19] = 0.000000024e18; // 0.000000024
        targetValuesPrecision[20] = 0.000000025e18; // 0.000000025
        targetValuesPrecision[21] = 0.000000026e18; // 0.000000026
        targetValuesPrecision[22] = 0.000000027e18; // 0.000000027
        targetValuesPrecision[23] = 0.000000028e18; // 0.000000028

        // Perform encoding and decoding test for each sliced array (from 2 to full length)
        for (uint256 i = 2; i <= targetValuesPrecision.length; i++) {
            // Create the test target values array by slicing the original array
            int256[] memory testTargetValues = new int256[](i);
            for (uint256 j = 0; j < i; j++) {
                testTargetValues[j] = targetValuesPrecision[targetValuesPrecision.length - i + j];
            }

            // Call the ExternalEncodeDecode32Array function from the contract
            int256[] memory redecoded = mockQuantAMMStorage.ExternalEncodeDecode32Array(
                testTargetValues,
                testTargetValues.length
            );

            // Check if the original and decoded arrays are the same
            checkResult(redecoded, testTargetValues);
        }
    }

    // Helper function to create a test matrix of size n x n
    function createMatrix(uint256 assets) internal pure returns (int256[][] memory) {
        int256[][] memory matrix = new int256[][](assets);
        for (uint256 i = 0; i < assets; i++) {
            matrix[i] = new int256[](assets);
            for (uint256 j = 0; j < assets; j++) {
                matrix[i][j] = int256((j + i * assets + 1) * 1e18); // Converting values to 18 decimal places
            }
        }
        return matrix;
    }

    // Test 1: Encoding and Decoding of the Smallest 2x2 Matrix
    function testSmallestMatrix() public {
        // Create a 2x2 test matrix
        int256[][] memory targetMatrix = createMatrix(2);

        // Call the ExternalEncodeDecodeMatrix function from the contract
        mockQuantAMMStorage.ExternalEncodeDecodeMatrix(targetMatrix);

        // Retrieve the decoded matrix and check
        int256[][] memory redecoded = mockQuantAMMStorage.GetMatrixResult();
        checkMatrixResult(redecoded, targetMatrix);
    }

    // Test 2: Encoding and Decoding of the Smallest Odd 3x3 Matrix
    function testSmallestOddMatrix() public {
        // Create a 3x3 test matrix
        int256[][] memory targetMatrix = createMatrix(3);

        // Call the ExternalEncodeDecodeMatrix function from the contract
        mockQuantAMMStorage.ExternalEncodeDecodeMatrix(targetMatrix);

        // Retrieve the decoded matrix and check
        int256[][] memory redecoded = mockQuantAMMStorage.GetMatrixResult();
        checkMatrixResult(redecoded, targetMatrix);
    }

    // Test 3: Encoding and Decoding of a Large Odd 11x11 Matrix
    function testLargeOddMatrix() public {
        // Create an 11x11 test matrix
        int256[][] memory targetMatrix = createMatrix(11);

        // Call the ExternalEncodeDecodeMatrix function from the contract
        mockQuantAMMStorage.ExternalEncodeDecodeMatrix(targetMatrix);

        // Retrieve the decoded matrix and check
        int256[][] memory redecoded = mockQuantAMMStorage.GetMatrixResult();
        checkMatrixResult(redecoded, targetMatrix);
    }

    // Test 4: Encoding and Decoding of a Large Even 12x12 Matrix
    function testLargeEvenMatrix() public {
        // Create a 12x12 test matrix
        int256[][] memory targetMatrix = createMatrix(12);

        // Call the ExternalEncodeDecodeMatrix function from the contract
        mockQuantAMMStorage.ExternalEncodeDecodeMatrix(targetMatrix);

        // Retrieve the decoded matrix and check
        int256[][] memory redecoded = mockQuantAMMStorage.GetMatrixResult();
        checkMatrixResult(redecoded, targetMatrix);
    }

    // Test 5: Encoding and Decoding of a Precision Matrix
    function testPrecisionMatrix() public {
        // Define the precision target matrix
        int256[][] memory targetMatrix = new int256[][](3);
        targetMatrix[0] = new int256[](3);
        targetMatrix[1] = new int256[](3);
        targetMatrix[2] = new int256[](3);
        targetMatrix[0][0] = 511111111111111111e18 + 17;
        targetMatrix[0][1] = 611111111111111111e18 + 18;
        targetMatrix[0][2] = 711111111111111111e18 + 21;
        targetMatrix[1][0] = 911111111111111111e18 + 23;
        targetMatrix[1][1] = 111111111111111111e18 + 24;
        targetMatrix[1][2] = 811111111111111111e18 + 18;
        targetMatrix[2][0] = 211111111111111111e18 + 25;
        targetMatrix[2][1] = 311111111111111111e18 + 26;
        targetMatrix[2][2] = 811111111111111111e18 + 19;

        // Call the ExternalEncodeDecodeMatrix function from the contract
        mockQuantAMMStorage.ExternalEncodeDecodeMatrix(targetMatrix);

        // Retrieve the decoded matrix and check
        int256[][] memory redecoded = mockQuantAMMStorage.GetMatrixResult();
        checkMatrixResult(redecoded, targetMatrix);
    }
}
