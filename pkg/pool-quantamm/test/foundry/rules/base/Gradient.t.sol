// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import { MockCalculationRule } from "../../../../contracts/mock/MockCalculationRule.sol";
import { MockPool } from "../../../../contracts/mock/MockPool.sol";
import { MockQuantAMMMathGuard } from "../../../../contracts/mock/MockQuantAMMMathGuard.sol";

import { QuantAMMTestUtils } from "../../utils.t.sol";

contract QuantAMMGradientTests is Test, QuantAMMTestUtils {
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

    // Function to test gradient calculation
    function testGradient(
        int256[][] memory priceData,
        int256[][] memory priceDataBn,
        int256[][] memory movingAverages,
        int256[] memory initialGradients,
        int128[] memory lambdas,
        int256[][] memory expectedRes
    ) internal {
        mockCalculationRule.setInitialGradient(address(mockPool), initialGradients, movingAverages[0].length);

        int256[][] memory results = new int256[][](movingAverages.length);

        require(priceData.length == priceDataBn.length, "1Length mismatch");
        require(priceData.length == movingAverages.length, "2Length mismatch");
        require(movingAverages.length == results.length, "3Length mismatch");
        for (uint256 i = 0; i < movingAverages.length; ++i) {
            mockCalculationRule.externalCalculateQuantAMMGradient(
                priceDataBn[i],
                movingAverages[i],
                address(mockPool),
                lambdas,
                initialGradients.length
            );
            results[i] = mockCalculationRule.getResults();
        }

        checkResult(priceData, results, expectedRes);
    }

    // Check results with tolerance
    function checkResult(
        int256[][] memory priceData,
        int256[][] memory res,
        int256[][] memory expectedRes
    ) internal pure {
        for (uint256 i = 0; i < priceData.length; i++) {
            for (uint256 j = 0; j < priceData[i].length; j++) {
                assertEq(res[i][j], expectedRes[i][j]); // Compare for exact equality
            }
        }
    }

    // Mock gradient calculation for different datasets
    // Scalar Lambda parameters
    // 2 tokens
    function testGradientCalculation2Tokens() public {
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
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1050), PRBMathSD59x18.fromInt(1050)],
                [PRBMathSD59x18.fromInt(1079) + 5e17, PRBMathSD59x18.fromInt(1078)],
                [PRBMathSD59x18.fromInt(1087) + 25e16, PRBMathSD59x18.fromInt(1088)]
            ]
        );

        int256[] memory gradients = new int256[](2);
        gradients[0] = PRBMathSD59x18.fromInt(0);
        gradients[1] = PRBMathSD59x18.fromInt(0);

        int128[] memory lambdas = new int128[](1);
        lambdas[0] = LAMBDA;

        int256[] memory lambdaNumbers = new int256[](1);
        lambdaNumbers[0] = 0.5e18;

        int256[][] memory expectedRes = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0)],
                [PRBMathSD59x18.fromInt(25), PRBMathSD59x18.fromInt(25)],
                [PRBMathSD59x18.fromInt(27) + 25e16, PRBMathSD59x18.fromInt(26) + 5e17],
                [PRBMathSD59x18.fromInt(17) + 5e17, PRBMathSD59x18.fromInt(18) + 25e16]
            ]
        );

        testGradient(priceData, priceDataBn, movingAverages, gradients, lambdas, expectedRes);
    }
    // 3 tokens
    function testGradientCalculation3Tokens() public {
        mockPool.setNumberOfAssets(3);

        int256[][] memory priceData = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100)],
                [PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105)],
                [PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108)],
                [PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111)]
            ]
        );

        int256[][] memory priceDataBn = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100)],
                [PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105)],
                [PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108)],
                [PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111)]
            ]
        );

        int256[][] memory movingAverages = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1050), PRBMathSD59x18.fromInt(1050), PRBMathSD59x18.fromInt(1050)],
                [
                    PRBMathSD59x18.fromInt(1077) + 5e17,
                    PRBMathSD59x18.fromInt(1077) + 5e17,
                    PRBMathSD59x18.fromInt(1077) + 5e17
                ],
                [
                    PRBMathSD59x18.fromInt(1092) + 75e16,
                    PRBMathSD59x18.fromInt(1092) + 75e16,
                    PRBMathSD59x18.fromInt(1092) + 75e16
                ],
                [
                    PRBMathSD59x18.fromInt(1101) + 875e15,
                    PRBMathSD59x18.fromInt(1101) + 875e15,
                    PRBMathSD59x18.fromInt(1101) + 875e15
                ]
            ]
        );

        int256[] memory gradients = new int256[](3);
        gradients[0] = PRBMathSD59x18.fromInt(0);
        gradients[1] = PRBMathSD59x18.fromInt(0);
        gradients[2] = PRBMathSD59x18.fromInt(0);

        int128[] memory lambdas = new int128[](1);
        lambdas[0] = LAMBDA;

        int256[] memory lambdaNumbers = new int256[](1);
        lambdaNumbers[0] = 0.5e18;

        int256[][] memory expectedRes = convert2DArrayToDynamic(
            [
                [PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0)],
                [PRBMathSD59x18.fromInt(25), PRBMathSD59x18.fromInt(25), PRBMathSD59x18.fromInt(25)],
                [
                    PRBMathSD59x18.fromInt(26) + 25e16,
                    PRBMathSD59x18.fromInt(26) + 25e16,
                    PRBMathSD59x18.fromInt(26) + 25e16
                ],
                [
                    PRBMathSD59x18.fromInt(20) + 75e16,
                    PRBMathSD59x18.fromInt(20) + 75e16,
                    PRBMathSD59x18.fromInt(20) + 75e16
                ],
                [
                    PRBMathSD59x18.fromInt(14) + 9375e14,
                    PRBMathSD59x18.fromInt(14) + 9375e14,
                    PRBMathSD59x18.fromInt(14) + 9375e14
                ]
            ]
        );

        testGradient(priceData, priceDataBn, movingAverages, gradients, lambdas, expectedRes);
    }
    // Vector Lambda parameters
    // 2 tokens
    function testGradientCalculation2TokensVectorLambda() public {
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
                [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
                [PRBMathSD59x18.fromInt(1050), PRBMathSD59x18.fromInt(1050)],
                [PRBMathSD59x18.fromInt(1079) + 5e17, PRBMathSD59x18.fromInt(1078)],
                [PRBMathSD59x18.fromInt(1087) + 25e16, PRBMathSD59x18.fromInt(1088)]
            ]
        );

        int256[] memory gradients = new int256[](2);
        gradients[0] = PRBMathSD59x18.fromInt(0);
        gradients[1] = PRBMathSD59x18.fromInt(0);

        int128[] memory lambdas = new int128[](2);
        lambdas[0] = LAMBDA;
        lambdas[1] = LAMBDA;

        int256[] memory lambdaNumbers = new int256[](2);
        lambdaNumbers[0] = 0.5e18;
        lambdaNumbers[1] = 0.5e18;

        int256[2][4] memory expectedResArray = [
            [PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0)],
            [PRBMathSD59x18.fromInt(25), PRBMathSD59x18.fromInt(25)],
            [PRBMathSD59x18.fromInt(27) + 25e16, PRBMathSD59x18.fromInt(26) + 5e17],
            [PRBMathSD59x18.fromInt(17) + 5e17, PRBMathSD59x18.fromInt(18) + 25e16]
        ];

        int256[][] memory expectedRes = convert2DArrayToDynamic(expectedResArray);

        testGradient(priceData, priceDataBn, movingAverages, gradients, lambdas, expectedRes);
    }
    // 3 tokens
    function testGradientCalculation3TokensVectorLambda() public {
        mockPool.setNumberOfAssets(3);

        int256[3][5] memory priceDataArray = [
            [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
            [PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100)],
            [PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105)],
            [PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108)],
            [PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111)]
        ];

        int256[][] memory priceData = convert2DArrayToDynamic(priceDataArray);
        int256[3][5] memory priceDataBnArray = [
            [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
            [PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100), PRBMathSD59x18.fromInt(1100)],
            [PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105), PRBMathSD59x18.fromInt(1105)],
            [PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108), PRBMathSD59x18.fromInt(1108)],
            [PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111), PRBMathSD59x18.fromInt(1111)]
        ];

        int256[][] memory priceDataBn = convert2DArrayToDynamic(priceDataBnArray);
        int256[3][5] memory averages = [
            [PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000), PRBMathSD59x18.fromInt(1000)],
            [PRBMathSD59x18.fromInt(1050), PRBMathSD59x18.fromInt(1050), PRBMathSD59x18.fromInt(1050)],
            [
                PRBMathSD59x18.fromInt(1077) + 5e17,
                PRBMathSD59x18.fromInt(1077) + 5e17,
                PRBMathSD59x18.fromInt(1077) + 5e17
            ],
            [
                PRBMathSD59x18.fromInt(1092) + 75e16,
                PRBMathSD59x18.fromInt(1092) + 75e16,
                PRBMathSD59x18.fromInt(1092) + 75e16
            ],
            [
                PRBMathSD59x18.fromInt(1101) + 875e15,
                PRBMathSD59x18.fromInt(1101) + 875e15,
                PRBMathSD59x18.fromInt(1101) + 875e15
            ]
        ];

        int256[][] memory movingAverages = convert2DArrayToDynamic(averages);

        int256[] memory gradients = new int256[](3);
        gradients[0] = PRBMathSD59x18.fromInt(0);
        gradients[1] = PRBMathSD59x18.fromInt(0);
        gradients[2] = PRBMathSD59x18.fromInt(0);

        int128[] memory lambdas = new int128[](3);
        lambdas[0] = LAMBDA;
        lambdas[1] = LAMBDA;
        lambdas[2] = int128(uint128(0.9e18));

        int256[] memory lambdaNumbers = new int256[](3);
        lambdaNumbers[0] = 0.5e18;
        lambdaNumbers[1] = 0.5e18;
        lambdaNumbers[2] = 0.9e18;

        int256[3][5] memory expectedResArray = [
            [PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0), PRBMathSD59x18.fromInt(0)],
            [PRBMathSD59x18.fromInt(25), PRBMathSD59x18.fromInt(25), int256(555555555555555500)],
            [PRBMathSD59x18.fromInt(26) + 25e16, PRBMathSD59x18.fromInt(26) + 25e16, int256(805555555555555475)],
            [PRBMathSD59x18.fromInt(20) + 75e16, PRBMathSD59x18.fromInt(20) + 75e16, int256(894444444444444355)],
            [PRBMathSD59x18.fromInt(14) + 9375e14, PRBMathSD59x18.fromInt(14) + 9375e14, int256(906388888888888798)]
        ];

        int256[][] memory expectedRes = convert2DArrayToDynamic(expectedResArray);

        testGradient(priceData, priceDataBn, movingAverages, gradients, lambdas, expectedRes);
    }
}
