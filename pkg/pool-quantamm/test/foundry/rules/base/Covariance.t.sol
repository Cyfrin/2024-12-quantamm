// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";

import { MockCalculationRule } from "../../../../contracts/mock/MockCalculationRule.sol";
import { MockPool } from "../../../../contracts/mock/MockPool.sol";
import { MockQuantAMMMathGuard } from "../../../../contracts/mock/MockQuantAMMMathGuard.sol";

import { QuantAMMTestUtils } from "../../utils.t.sol";

contract QuantAMMVarianceTest is Test, QuantAMMTestUtils {
    using PRBMathSD59x18 for int256;

    MockCalculationRule mockCalculationRule;
    MockPool mockPool;
    MockQuantAMMMathGuard mockQuantAMMMathGuard;

    int256 constant UPDATE_INTERVAL = 1800e18; // 1800 seconds in fixed-point format
    int128 constant LAMBDA = 5e17; // Lambda is 0.5 in fixed-point format

    function setUp() public {
        mockCalculationRule = new MockCalculationRule();
        mockPool = new MockPool(3600, 1e18, address(mockCalculationRule)); // 3600 sec update interval
        mockQuantAMMMathGuard = new MockQuantAMMMathGuard();
    }

    // Utility to compare results with some tolerance
    function closeTo(int256 a, int256 b, int256 tolerance) internal pure {
        int256 delta = (a - b).abs();
        require(delta <= tolerance, "Values are not within tolerance");
    }

    // Function to test covariance calculation
    function testCovariance(
        int256[][] memory priceData,
        int256[][] memory priceDataBn,
        int256[][] memory movingAverages,
        int256[][] memory initialCovariance,
        int256[][][] memory expectedRes
    ) internal {
        mockCalculationRule.setInitialCovariance(address(mockPool), initialCovariance, priceData[0].length);
        mockCalculationRule.setPrevMovingAverage(movingAverages[0]);

        int256[][][] memory results = new int256[][][](movingAverages.length);

        for (uint256 i = 0; i < movingAverages.length; ++i) {
            if (i > 0) {
                mockCalculationRule.setPrevMovingAverage(movingAverages[i - 1]);
            }
            int128[] memory lambda = new int128[](1);
            lambda[0] = int128(uint128(0.5e18));
            mockCalculationRule.externalCalculateQuantAMMCovariance(
                priceDataBn[i],
                movingAverages[i],
                address(mockPool),
                lambda,
                initialCovariance[0].length
            );
            results[i] = mockCalculationRule.getMatrixResults();
        }

        checkCovarianceResult(priceData, results, expectedRes);
    }

    function checkCovarianceResult(
        int256[][] memory priceData,
        int256[][][] memory res,
        int256[][][] memory expectedRes
    ) internal pure {
        uint256 n = priceData[0].length;
        for (uint256 i = 0; i < res.length; i++) {
            for (uint256 j = 0; j < n; j++) {
                for (uint256 k = 0; k < n; k++) {
                    assertEq(res[i][j][k], expectedRes[i][j][k], "Values are not the same");
                }
            }
        }
    }

    // Covariance Matrix Calculation
    // 2 tokens
    function testCovarianceCalculation2Tokens() public {
        mockPool.setNumberOfAssets(2);
        int256[][] memory priceData = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100)],
                [PRBMathSD59x18.fromInt(1109), PRBMathSD59x18.fromInt(1106)],
                [PRBMathSD59x18.fromInt(1095), PRBMathSD59x18.fromInt(1098)]
            ]
        );

        int256[][] memory priceDataBn = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100)],
                [PRBMathSD59x18.fromInt(1109), PRBMathSD59x18.fromInt(1106)],
                [PRBMathSD59x18.fromInt(1095), PRBMathSD59x18.fromInt(1098)]
            ]
        );

        int256[][] memory movingAverages = convert2DArrayToDynamic(
            [
                [
                    PRBMathSD59x18.fromInt(1000),
                    PRBMathSD59x18.fromInt(1000),
                    PRBMathSD59x18.fromInt(1000),
                    PRBMathSD59x18.fromInt(1000)
                ],
                [
                    PRBMathSD59x18.fromInt(1050),
                    PRBMathSD59x18.fromInt(1050),
                    PRBMathSD59x18.fromInt(1000),
                    PRBMathSD59x18.fromInt(1000)
                ],
                [
                    PRBMathSD59x18.fromInt(1079) + 5e17,
                    PRBMathSD59x18.fromInt(1078),
                    PRBMathSD59x18.fromInt(1050),
                    PRBMathSD59x18.fromInt(1050)
                ],
                [
                    PRBMathSD59x18.fromInt(1087) + 25e16,
                    PRBMathSD59x18.fromInt(1088),
                    PRBMathSD59x18.fromInt(1079) + 5e17,
                    PRBMathSD59x18.fromInt(1078)
                ]
            ]
        );

        int256[][] memory initialCovariance = new int256[][](2);
        initialCovariance[0] = new int256[](2);
        initialCovariance[0][0] = 0;
        initialCovariance[0][1] = 0;
        initialCovariance[1] = new int256[](2);
        initialCovariance[1][0] = 0;
        initialCovariance[1][1] = 0;

        int256[][][] memory expectedRes = covert3DArrayToDynamic(
            [
                [
                    [PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0)],
                    [PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0)]
                ],
                [
                    [PRBMathSD59x18.fromInt(2500), PRBMathSD59x18.fromInt(2500)],
                    [PRBMathSD59x18.fromInt(2500), PRBMathSD59x18.fromInt(2500)]
                ],
                [
                    [PRBMathSD59x18.fromInt(2120) + 25e16, PRBMathSD59x18.fromInt(2076)],
                    [PRBMathSD59x18.fromInt(2076), PRBMathSD59x18.fromInt(2034)]
                ],
                [
                    [PRBMathSD59x18.fromInt(1120) + 1875e14, PRBMathSD59x18.fromInt(1115) + 5e17],
                    [PRBMathSD59x18.fromInt(1115) + 5e17, PRBMathSD59x18.fromInt(1117)]
                ]
            ]
        );

        testCovariance(priceData, priceDataBn, movingAverages, initialCovariance, expectedRes);
    }
}
