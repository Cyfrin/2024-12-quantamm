// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import "../../../contracts/mock/MockRuleInvoker.sol";
import "../../../contracts/mock/mockRules/MockPowerChannelRule.sol";
import "../../../contracts/mock/MockPool.sol";
import "../utils.t.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PowerChannelUpdateRuleTest is Test, QuantAMMTestUtils {
    MockPowerChannelRule rule;
    MockPool mockPool;

    function setUp() public {
        // Deploy Power Channel Rule contract
        rule = new MockPowerChannelRule(address(this));

        // Deploy Mock Pool contract
        mockPool = new MockPool(3600, PRBMathSD59x18.fromInt(1), address(rule));
    }

    function testEmptyParametersShouldNotBeAccepted() public view {
        int256[][] memory emptyParams;
        bool valid = rule.validParameters(emptyParams); // Passing empty parameters
        assertFalse(valid);
    }

    function testKappaZeroQGreaterThanOneShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(0); // kappa = 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(2); // q > 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testVectorKappaZeroQGreaterThanOneShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(0); // kappa = 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(2); // q > 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }


    function testFuzz_KappaZeroQGreaterThanOneShouldNotBeAccepted(int256 q) public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(0); // kappa = 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(bound(q, 1, maxScaledFixedPoint18())); // q > 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }


    function testFuzz_VectorKappaZeroQGreaterThanOneShouldNotBeAccepted(int256 vectorParams, int256 q) public view {
        int256[][] memory parameters = new int256[][](2);
        uint256 paramCount = uint256(bound(vectorParams, 2, 10));
        parameters[0] = new int256[](paramCount);
        parameters[1] = new int256[](paramCount);
        for(uint i = 0; i < paramCount; i++) {
            if(i == 0) {
                parameters[0][i] = PRBMathSD59x18.fromInt(1); // kappa = 1
            } else {
                parameters[0][i] = PRBMathSD59x18.fromInt(0); // kappa = 1
            }
            parameters[1][i] = PRBMathSD59x18.fromInt(bound(q, 1, maxScaledFixedPoint18())); // q > 1
        }

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testKappaGreaterThanZeroQGreaterThanOneShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(1); // kappa > 0
        parameters[1] = new int256[](1);
        parameters[1][0] = 2e18; // q > 1

        bool valid = rule.validParameters(parameters);
        assertTrue(valid);
    }


    function testVectorKappaGreaterThanZeroQGreaterThanOneShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1); // kappa > 0
        parameters[0][1] = PRBMathSD59x18.fromInt(1); // kappa > 0
        parameters[1] = new int256[](2);
        parameters[1][0] = 2e18; // q > 1
        parameters[1][1] = 2e18; // q > 1

        bool valid = rule.validParameters(parameters);
        assertTrue(valid);
    }

    function testVectorKappaQDifferentLengthsShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(1); // kappa > 0
        parameters[0][1] = PRBMathSD59x18.fromInt(1); // kappa > 0
        parameters[1] = new int256[](1);
        parameters[1][0] = 2e18; // q > 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testKappaGreaterThanZeroQEqualToOneShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(1); // kappa > 0
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(1); // q = 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testFuzz_KappaGreaterThanZeroQEqualToOneShouldNotBeAccepted(int256 kappa) public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(bound(kappa, 1, maxScaledFixedPoint18())); // kappa > 0
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(1); // q = 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testKappaLessThanZeroQGreaterThanOneShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(-1); // kappa < 0
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(2); // q > 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }


// Function that tests correct weights with lower prices
    function testParameters3WithLength2ShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[1][1] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(0); // Parameter 3

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testFuzz_KappaLessThanZeroQGreaterThanOneShouldNotBeAccepted(
        int256 kappa,
        int256 q
    ) public view {
        int256[][] memory parameters = new int256[][](2);
        parameters[0] = new int256[](1);
        parameters[0][0] = -PRBMathSD59x18.fromInt(bound(kappa, 1, maxScaledFixedPoint18())); // kappa < 0
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(bound(q, 1, maxScaledFixedPoint18())); // q > 1

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testCorrectWeightsWithHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(5);
        data[1] = PRBMathSD59x18.fromInt(6);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.500035215760277504e18;
        expectedResults[1] = 0.499964784239722496e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithLowerPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.499867557750343680e18;
        expectedResults[1] = 0.500132442249656320e18;

        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }

    function testCorrectWeightsWithVectorParamsHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[1][1] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(1); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(5);
        data[1] = PRBMathSD59x18.fromInt(6);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.500066288489934848e18;
        expectedResults[1] = 0.499933711510077440e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithVectorParamsLowerPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[1][1] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(1); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18); // Lambda = 0.9

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.499750696941821952e18;
        expectedResults[1] = 0.500249303058153472e18;

        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }

    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithVectorParamsVectorqLowerPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(1); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18); // Lambda = 0.9

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.496497130970298368e18;
        expectedResults[1] = 0.503502869029683200e18;
        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    function testCorrectWeightsWithVectorParamsVectorqHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(1); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(5);
        data[1] = PRBMathSD59x18.fromInt(6);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.502825521901510656e18;
        expectedResults[1] = 0.497174478098497536e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithVectorqLowerPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.498139100827971584e18;
        expectedResults[1] = 0.501860899172028416e18;

        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    function testCorrectWeightsWithVectorqHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(1); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.500002074426347520e18;
        expectedResults[1] = 0.499997925573652480e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    function testCorrectWeightsWithUseMovingAverageHigherPrices() public {
                int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(5);
        data[1] = PRBMathSD59x18.fromInt(6);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.500247564531423232e18;
        expectedResults[1] = 0.499752435468576768e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithUseMovingAverageLowerPrice() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.499960667777880064e18;
        expectedResults[1] = 0.500039332222119936e18;

        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }

    function testCorrectWeightsWithVectorParamsWithUseMovingAverageHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[1][1] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(0); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.499999830448801792e18;
        expectedResults[1] = 0.500000169551200256e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithVectorParamsUseMovingAverageLowerPrice() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[1][1] = PRBMathSD59x18.fromInt(3); // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(0); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18); // Lambda = 0.9

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        
        expectedResults[0] = 0.499925962876008448e18;
        expectedResults[1] = 0.500074037123973120e18;

        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }

    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithVectorParamsVectorqUseMovingAverageLowerPrice() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(0); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18); // Lambda = 0.9

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.498728849640292352e18;
        expectedResults[1] = 0.501271150359674880e18;
        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    function testCorrectWeightsWithVectorParamsVectorqWithUseMovingAverageHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[0][1] = PRBMathSD59x18.fromInt(32768); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](2);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3
        parameters[2][1] = PRBMathSD59x18.fromInt(0); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.500003904802537472e18;
        expectedResults[1] = 0.499996095197478912e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    // Function that tests correct weights with lower prices
    function testCorrectWeightsWithVectorqUseMovingAverageLowerPrice() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3

        // Alpha and moving averages initialization
        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        // Weights initialization
        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        // Data (new prices) initialization
        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(2); // New price 1
        data[1] = PRBMathSD59x18.fromInt(4); // New price 2

        // Expected result weights
        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.499324701371406336e18;
        expectedResults[1] = 0.500675298628593664e18;

        mockPool.setNumberOfAssets(2);

        // Call the rule function and get the result
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        // Get the updated weights
        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
    function testCorrectWeightsWithVectorqWithUseMovingAverageHigherPrices() public {
        int256[][] memory parameters = new int256[][](3);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2048); // Parameter 1
        parameters[1] = new int256[](2);
        parameters[1][0] = 2.5e18; // Parameter 2
        parameters[1][1] = 3.5e18; // Parameter 2
        parameters[2] = new int256[](1);
        parameters[2][0] = PRBMathSD59x18.fromInt(0); // Parameter 3

        int256[] memory prevAlphas = new int256[](2);
        prevAlphas[0] = PRBMathSD59x18.fromInt(1);
        prevAlphas[1] = PRBMathSD59x18.fromInt(2);

        int256[] memory prevMovingAverages = new int256[](2);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(3);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory movingAverages = new int256[](2);
        movingAverages[0] = PRBMathSD59x18.fromInt(3);
        movingAverages[1] = PRBMathSD59x18.fromInt(4);

        // Lambda initialization
        int128[] memory lambdas = new int128[](1);
        lambdas[0] = int128(0.9e18);

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18; // Weight 1
        prevWeights[1] = 0.5e18; // Weight 2

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory expectedResults = new int256[](2);
        expectedResults[0] = 0.500002074426347520e18;
        expectedResults[1] = 0.499997925573652480e18;

        mockPool.setNumberOfAssets(2);

        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            prevAlphas,
            mockPool.numAssets()
        );

        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambdas, movingAverages);

        int256[] memory resultWeights = rule.GetResultWeights();

        checkResult(resultWeights, expectedResults);
    }
}
