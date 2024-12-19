// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import "../../../contracts/mock/MockRuleInvoker.sol";
import "../../../contracts/mock/mockRules/MockDifferenceMomentumRule.sol";
import "../../../contracts/mock/MockPool.sol";
import "../utils.t.sol";

contract DifferenceMomentumRuleTest is Test, QuantAMMTestUtils {
    MockDifferenceMomentumRule public rule;
    MockPool public mockPool;
    address internal owner;
    address internal addr1;
    address internal addr2;

    function setUp() public {
        (address ownerLocal, address addr1Local, address addr2Local) = (vm.addr(1), vm.addr(2), vm.addr(3));
        owner = ownerLocal;
        addr1 = addr1Local;
        addr2 = addr2Local;

        // Deploying MockMomentumRule contract
        rule = new MockDifferenceMomentumRule(owner);

        // Deploy MockPool contract with some mock parameters
        mockPool = new MockPool(3600, 1 ether, address(rule));
    }

    function runInitialUpdate(
        uint256 numAssets,
        int256[][] memory parameters,
        int256[] memory prevShortMovingAverage,
        int256[] memory prevMovingAverages,
        int256[] memory movingAverages,
        int128[] memory lambdas,
        int256[] memory prevWeights,
        int256[] memory data,
        int256[] memory results
    ) internal {
        // Simulate setting number of assets and calculating intermediate values
        mockPool.setNumberOfAssets(numAssets);
        vm.startPrank(owner);
        rule.initialisePoolRuleIntermediateValues(address(mockPool), prevMovingAverages, prevShortMovingAverage, numAssets);

        // Run calculation for unguarded weights
        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);
        vm.stopPrank();

        // Check results against expected weights
        int256[] memory res = rule.GetResultWeights();
        checkResult(res, results);
    }

    function testNoninitialisedParametersShouldNotBeAccepted() public view {
        int256[][] memory parameters;
        bool result = rule.validParameters(parameters);
        assertFalse(result);
    }

    function testEmptyParametersShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        bool result = rule.validParameters(parameters);
        assertFalse(result);
    }

    function testEmpty1DParametersShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](1);
        bool result = rule.validParameters(parameters);
        assertFalse(result);
    }

    function testZeroShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(0);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertFalse(result);
    }

    function testPositiveNumberShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(42);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }

    function testNegativeNumberShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(-42);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }


    function testZeroShouldBeAccepted_VectorParams() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(0);
        parameters[0][1] = PRBMathSD59x18.fromInt(1);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertFalse(result);
    }

    function testPositiveNumberShouldBeAccepted_VectorParams() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(42);
        parameters[0][1] = PRBMathSD59x18.fromInt(42);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }

    function testNegativeNumberShouldBeAccepted_VectorParams() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(-42);
        parameters[0][1] = PRBMathSD59x18.fromInt(-42);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }


    function testMixedNumberShouldBeAccepted_VectorParams() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(42);
        parameters[0][1] = PRBMathSD59x18.fromInt(-42);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }
    function testFuzz_TestPositiveNumberShouldBeAccepted(int256 param) public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(bound(param, 1, maxScaledFixedPoint18()));
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }


    function testFuzz_TestNegativeNumberShouldBeAccepted(int256 param) public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = -PRBMathSD59x18.fromInt(bound(param, 1, maxScaledFixedPoint18()));
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }

    function testVectorParamTestZeroShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[0][1] = PRBMathSD59x18.fromInt(0);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertFalse(result);
    }

    function testVectorParamTestPositiveNumberShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(42);
        parameters[0][1] = PRBMathSD59x18.fromInt(42);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }

    function testVectorParamTestNegativeNumberShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[0][1] = -PRBMathSD59x18.fromInt(1);
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.5e18;
        bool result = rule.validParameters(parameters);
        assertTrue(result);
    }

    function testCorrectUpdateWithHigherPrice_scalarParams() public {
        /*
            ℓp(t)	0.10125	
            moving average	[0.9, 1.2]
            alpha	[7.7, 10.73333333]
            beta	[0.297,	0.414]
            new weight	[0.49775, 0.50225]
        */

        // Define local variables for the parameters
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(0);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(0);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = 0.9e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.2e18;

        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.361111111111111112e18;
        expectedResults[1] = 0.638888888888888889e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithLowerPrices_scalarParams() public {
        /*
            moving average	2.7	4
            alpha	-1.633333333	1.4
            beta	-0.063	0.054
            new weight	0.4775	0.5225
        */

        // Define local variables for the parameters
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(2) + 0.7e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.402777777777777778e18;
        expectedResults[1] = 0.597222222222222222e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithHigherPrices_VectorParams() public {
        // Define local variables for the parameters
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[0][1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.5e18;
        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](2);
        lambdas[0] = int128(0.7e18);
        lambdas[1] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.45e18;
        expectedResults[1] = 0.55e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithLowerPrices_VectorParams() public {
        // Define local variables for the parameters

        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[0][1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.5e18;


        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(2) + 0.7e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(4);


        int128[] memory lambdas = new int128[](2);
        lambdas[0] = int128(0.7e18);
        lambdas[1] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.383333333333333333e18;
        expectedResults[1] = 0.616666666666666666e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithHigherPrices_scalarParams_negativeKappa() public {
        /*
            ℓp(t)	0.10125	
            moving average	[0.9, 1.2]
            alpha	[7.7, 10.73333333]
            beta	[0.297,	0.414]
            new weight	[0.49775, 0.50225]
        */

        // Define local variables for the parameters
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = -PRBMathSD59x18.fromInt(1);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(0);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(0);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = 0.9e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.2e18;

        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        //rounding is fine. Gets normalised during guard process
        expectedResults[0] = 0.638888888888888888e18;
        expectedResults[1] = 0.361111111111111111e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithLowerPrices_scalarParams_negativeKappa() public {
        /*
            moving average	2.7	4
            alpha	-1.633333333	1.4
            beta	-0.063	0.054
            new weight	0.4775	0.5225
        */

        // Define local variables for the parameters
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = -PRBMathSD59x18.fromInt(1);
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(2) + 0.7e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.597222222222222222e18;
        expectedResults[1] = 0.402777777777777778e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithHigherPrices_VectorParams_negativeKappa() public {
        // Define local variables for the parameters
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = -PRBMathSD59x18.fromInt(1);
        parameters[0][1] = -PRBMathSD59x18.fromInt(1) - 0.5e18;
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.5e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](2);
        lambdas[0] = int128(0.7e18);
        lambdas[1] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.55e18;
        expectedResults[1] = 0.45e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithLowerPrices_VectorParams_negativeKappa() public {
        // Define local variables for the parameters

        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = -PRBMathSD59x18.fromInt(1);
        parameters[0][1] = -PRBMathSD59x18.fromInt(1) - 0.5e18;
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.5e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(2) + 0.7e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](2);
        lambdas[0] = int128(0.7e18);
        lambdas[1] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.616666666666666667e18;
        expectedResults[1] = 0.383333333333333334e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }


    function testCorrectUpdateWithLowerPrices_VectorParams_differentShortLambda() public {
        // Define local variables for the parameters

        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1);
        parameters[0][1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.3e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(2) + 0.7e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](2);
        lambdas[0] = int128(0.7e18);
        lambdas[1] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.323333333333333333e18;
        expectedResults[1] = 0.676666666666666666e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }

    function testCorrectUpdateWithLowerPrices_VectorParams_negativeKappa_differentShortLambda() public {
        // Define local variables for the parameters

        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = -PRBMathSD59x18.fromInt(1);
        parameters[0][1] = -PRBMathSD59x18.fromInt(1) - 0.5e18;
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18;
        parameters[1][1] = 0.3e18;

        int256[] memory prevShortMovingAverage = new int256[](2);
        prevShortMovingAverage[0] = PRBMathSD59x18.fromInt(1);
        prevShortMovingAverage[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(2) + 0.7e18;
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        int128[] memory lambdas = new int128[](2);
        lambdas[0] = int128(0.7e18);
        lambdas[1] = int128(0.7e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.676666666666666667e18;
        expectedResults[1] = 0.323333333333333334e18;

        // Now pass the variables into the runInitialUpdate function
        runInitialUpdate(
            2, // numAssets
            parameters,
            prevShortMovingAverage,
            prevMovingAverages,
            movingAverages,
            lambdas,
            prevWeights,
            data,
            expectedResults
        );
    }
}
