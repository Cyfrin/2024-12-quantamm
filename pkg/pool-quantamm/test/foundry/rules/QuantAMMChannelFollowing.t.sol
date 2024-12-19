// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import "../../../contracts/mock/MockRuleInvoker.sol";
import "../../../contracts/mock/mockRules/MockChannelFollowing.sol";
import "../../../contracts/mock/MockPool.sol";
import "../utils.t.sol";

contract ChannelFollowingUpdateRuleTest is Test, QuantAMMTestUtils {
    MockChannelFollowingRule rule;
    MockPool mockPool;

    function setUp() public {
        // Deploy Power Channel Rule contract
        rule = new MockChannelFollowingRule(address(this));

        // Deploy Mock Pool contract
        mockPool = new MockPool(3600, PRBMathSD59x18.fromInt(1), address(rule));
    }

    function testEmptyParametersShouldNotBeAccepted() public view {
        int256[][] memory emptyParams;
        bool valid = rule.validParameters(emptyParams); // Passing empty parameters
        assertFalse(valid);
    }

    function testNegativeScalarParametersShouldNotBeAccepted() public view {
        // Test each parameter being negative while others are valid
        int256[][] memory parameters = new int256[][](7);
        
        // Base case - all parameters valid
        for (uint i = 0; i < 6; i++) {
            parameters[i] = new int256[](1);
            parameters[i][0] = PRBMathSD59x18.fromInt(1); // Valid positive value
        }
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 can be 0

        // Test each parameter being negative
        for (uint i = 0; i < 6; i++) {
            int256[][] memory testParams = parameters;
            testParams[i][0] = PRBMathSD59x18.fromInt(-1); // Set parameter negative
            bool valid = rule.validParameters(testParams);
            assertFalse(valid);
        }
    }

    function testNegativeVectorParametersShouldNotBeAccepted() public view {
        // Test each parameter being negative while others are valid
        int256[][] memory parameters = new int256[][](7);
        
        // Base case - all parameters valid with 2 assets
        for (uint i = 0; i < 6; i++) {
            parameters[i] = new int256[](2);
            parameters[i][0] = PRBMathSD59x18.fromInt(1); // Valid positive value
            parameters[i][1] = PRBMathSD59x18.fromInt(1); // Valid positive value
        }
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 can be 0

        // Test each parameter being negative
        for (uint i = 0; i < 6; i++) {
            int256[][] memory testParams = parameters;
            testParams[i][0] = PRBMathSD59x18.fromInt(-1); // Set first parameter negative
            testParams[i][1] = PRBMathSD59x18.fromInt(-1); // Set second parameter negative
            bool valid = rule.validParameters(testParams);
            assertFalse(valid);
        }
    }

    function testFuzz_NegativeScalarParametersShouldNotBeAccepted(
        int256 param1,
        int256 param2,
        int256 param3,
        int256 param4,
        int256 param5,
        int256 param6
    ) public view {
        int256[][] memory parameters = new int256[][](7);
        
        // Initialize all parameters as valid positive values
        for (uint i = 0; i < 6; i++) {
            parameters[i] = new int256[](1);
            parameters[i][0] = PRBMathSD59x18.fromInt(1);
        }
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 can be 0

        // Set each parameter to the fuzzed negative value
        parameters[0][0] = -PRBMathSD59x18.fromInt(bound(param1, 1, maxScaledFixedPoint18()));
        parameters[1][0] = -PRBMathSD59x18.fromInt(bound(param2, 1, maxScaledFixedPoint18()));
        parameters[2][0] = -PRBMathSD59x18.fromInt(bound(param3, 1, maxScaledFixedPoint18()));
        parameters[3][0] = -PRBMathSD59x18.fromInt(bound(param4, 1, maxScaledFixedPoint18()));
        parameters[4][0] = -PRBMathSD59x18.fromInt(bound(param5, 1, maxScaledFixedPoint18()));
        parameters[5][0] = -PRBMathSD59x18.fromInt(bound(param6, 1, maxScaledFixedPoint18()));

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }

    function testFuzz_NegativeVectorParametersShouldNotBeAccepted(
        uint8 numTokens,
        int256 param1,
        int256 param2,
        int256 param3,
        int256 param4,
        int256 param5,
        int256 param6
    ) public view {
        // Bound number of tokens between 1 and 10 to keep test reasonable
        numTokens = uint8(bound(numTokens, 1, 10));
        
        int256[][] memory parameters = new int256[][](7);
        
        // Initialize all parameters as valid positive values with numTokens length
        for (uint i = 0; i < 6; i++) {
            parameters[i] = new int256[](numTokens);
            for (uint j = 0; j < numTokens; j++) {
                // Set each parameter to a valid positive value based on its meaning
                if (i == 0) { // kappa
                    parameters[i][j] = PRBMathSD59x18.fromInt(200);
                } else if (i == 1) { // width 
                    parameters[i][j] = 0.5e18;
                } else if (i == 2) { // amplitude
                    parameters[i][j] = 0.1e18;
                } else if (i == 3) { // exponents
                    parameters[i][j] = 2.5e18;
                } else if (i == 4) { // inverse scaling
                    parameters[i][j] = 0.8e18;
                } else if (i == 5) { // pre-exp scaling
                    parameters[i][j] = 0.5e18;
                }
            }
        }
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 can be 0

        // Set each parameter array to contain negative values
        for (uint j = 0; j < numTokens; j++) {
            parameters[0][j] = -PRBMathSD59x18.fromInt(bound(param1, 1, maxScaledFixedPoint18()));
            parameters[1][j] = -PRBMathSD59x18.fromInt(bound(param2, 1, maxScaledFixedPoint18()));
            parameters[2][j] = -PRBMathSD59x18.fromInt(bound(param3, 1, maxScaledFixedPoint18()));
            parameters[3][j] = -PRBMathSD59x18.fromInt(bound(param4, 1, maxScaledFixedPoint18()));
            parameters[4][j] = -PRBMathSD59x18.fromInt(bound(param5, 1, maxScaledFixedPoint18()));
            parameters[5][j] = -PRBMathSD59x18.fromInt(bound(param6, 1, maxScaledFixedPoint18()));
        }

        bool valid = rule.validParameters(parameters);
        assertFalse(valid);
    }


    function testFuzz_SeventhParamOnlyZeroOrOne(uint8 numTokens, int256 param7) public view {
        // Bound number of tokens between 1 and 10 to keep test reasonable
        numTokens = uint8(bound(numTokens, 1, 10));
        int256[][] memory parameters = new int256[][](7);
        
        // Initialize first 6 parameter arrays with valid values
        for (uint i = 0; i < 6; i++) {
            parameters[i] = new int256[](numTokens);
            for (uint j = 0; j < numTokens; j++) {
                if (i == 0) { // kappa
                    parameters[i][j] = PRBMathSD59x18.fromInt(200);
                } else if (i == 1) { // width 
                    parameters[i][j] = 0.5e18;
                } else if (i == 2) { // amplitude
                    parameters[i][j] = 0.1e18;
                } else if (i == 3) { // exponents
                    parameters[i][j] = 2.5e18;
                } else if (i == 4) { // inverse scaling
                    parameters[i][j] = 0.8e18;
                } else if (i == 5) { // pre-exp scaling
                    parameters[i][j] = 0.5e18;
                }
            }
        }
        // Set up 7th parameter array
        parameters[6] = new int256[](1);
        
        // Choose between valid and invalid values with equal probability
        int256 shouldBeValid = param7 % 2;
        // For valid cases, test both 0 and 1e18
        if (shouldBeValid == 0) {
            parameters[6][0] = (param7 % 2 == 0) ? int256(0) : PRBMathSD59x18.fromInt(1);
            assertTrue(rule.validParameters(parameters), "Parameters should be valid when param7 is 0 or 1e18");
        }
        // For invalid cases, test an arbitrary invalid value
        else {
            parameters[6][0] = PRBMathSD59x18.fromInt(2); // Any value besides 0 or 1
            assertFalse(rule.validParameters(parameters), "Parameters should be invalid when param7 is not 0 or 1e18");
        }
    }

    function testFuzz_OnlySevenParamsAccepted(uint8 numParams) public view {
        // Bound number of parameters between 1 and 20 to keep test reasonable
        // Exclude 7 since that's the valid case
        numParams = uint8(bound(numParams, 1, 20));
        if (numParams == 7) numParams = 8;

        int256[][] memory parameters = new int256[][](numParams);
        
        // Fill all parameter arrays with scalar value 1
        for (uint i = 0; i < numParams; i++) {
            parameters[i] = new int256[](1);
            parameters[i][0] = PRBMathSD59x18.fromInt(1);
        }

        bool valid = rule.validParameters(parameters);
        assertFalse(valid, "Parameters should be invalid when length is not 7");
    }

    function testCorrectWeightsWithHigherPrices() public {
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[2] = new int256[](1);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](1);
        parameters[3][0] = PRBMathSD59x18.fromInt(3); // Parameter 4 Exponents
        parameters[4] = new int256[](1);
        parameters[4][0] = PRBMathSD59x18.fromInt(1); // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](1);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(1); // Parameter 7 Use Raw Price

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
        expectedResults[0] = 0.487280456264591400e18;
        expectedResults[1] = 0.512719543735408600e18;

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
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[2] = new int256[](1);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](1);
        parameters[3][0] = PRBMathSD59x18.fromInt(3); // Parameter 4 Exponents
        parameters[4] = new int256[](1);
        parameters[4][0] = PRBMathSD59x18.fromInt(1); // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](1);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(1); // Parameter 7 Use Raw Price

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
        expectedResults[0] = 0.616347884950068200e18;
        expectedResults[1] = 0.383652115049931800e18;

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
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[0][1] = PRBMathSD59x18.fromInt(400); // Parameter 1 Kappa
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[1][1] = 1.5e18; // Parameter 2 Width
        parameters[2] = new int256[](2);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[2][1] = 0.2e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](2);
        parameters[3][0] = 2.5e18; // Parameter 4 Exponents
        parameters[3][1] = 3.5e18; // Parameter 4 Exponents
        parameters[4] = new int256[](2);
        parameters[4][0] = 0.8e18; // Parameter 5 Inverse Scaling
        parameters[4][1] = 1e18; // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](2);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[5][1] = 0.3e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(1); // Parameter 7 Use Raw Price

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
        expectedResults[0] = 0.413044386615075800e18;
        expectedResults[1] = 0.586955613384924000e18;

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
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[0][1] = PRBMathSD59x18.fromInt(400); // Parameter 1 Kappa
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[1][1] = 1.5e18; // Parameter 2 Width
        parameters[2] = new int256[](2);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[2][1] = 0.2e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](2);
        parameters[3][0] = 2.5e18; // Parameter 4 Exponents
        parameters[3][1] = 3.5e18; // Parameter 4 Exponents
        parameters[4] = new int256[](2);
        parameters[4][0] = 0.8e18; // Parameter 5 Inverse Scaling
        parameters[4][1] = 1e18; // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](2);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[5][1] = 0.3e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(1); // Parameter 7 Use Raw Price

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
        expectedResults[0] = 0.685768271666430200e18;
        expectedResults[1] = 0.314231728333570000e18;

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

    function testCorrectWeightsWithUseMovingAverageHigherPrices() public {
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[2] = new int256[](1);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](1);
        parameters[3][0] = PRBMathSD59x18.fromInt(3); // Parameter 4 Exponents
        parameters[4] = new int256[](1);
        parameters[4][0] = PRBMathSD59x18.fromInt(1); // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](1);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 Don't use raw price


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
        expectedResults[0] = 0.464719395233870000e18;
        expectedResults[1] = 0.535280604766130000e18;

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
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[1] = new int256[](1);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[2] = new int256[](1);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](1);
        parameters[3][0] = PRBMathSD59x18.fromInt(3); // Parameter 4 Exponents
        parameters[4] = new int256[](1);
        parameters[4][0] = PRBMathSD59x18.fromInt(1); // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](1);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 Don't use raw price

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
        expectedResults[0] = 0.581058650366410200e18;
        expectedResults[1] = 0.418941349633589800e18;

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
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[0][1] = PRBMathSD59x18.fromInt(400); // Parameter 1 Kappa
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[1][1] = 1.5e18; // Parameter 2 Width
        parameters[2] = new int256[](2);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[2][1] = 0.2e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](2);
        parameters[3][0] = 2.5e18; // Parameter 4 Exponents
        parameters[3][1] = 3.5e18; // Parameter 4 Exponents
        parameters[4] = new int256[](2);
        parameters[4][0] = 0.8e18; // Parameter 5 Inverse Scaling
        parameters[4][1] = 1e18; // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](2);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[5][1] = 0.3e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 Don't use raw price

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
        expectedResults[0] = 0.497672897155407600e18;
        expectedResults[1] = 0.502327102844592400e18;

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
        int256[][] memory parameters = new int256[][](7);
        parameters[0] = new int256[](2);
        parameters[0][0] = PRBMathSD59x18.fromInt(200); // Parameter 1 Kappa
        parameters[0][1] = PRBMathSD59x18.fromInt(400); // Parameter 1 Kappa
        parameters[1] = new int256[](2);
        parameters[1][0] = 0.5e18; // Parameter 2 Width
        parameters[1][1] = 1.5e18; // Parameter 2 Width
        parameters[2] = new int256[](2);
        parameters[2][0] = 0.1e18; // Parameter 3 Amplitude
        parameters[2][1] = 0.2e18; // Parameter 3 Amplitude
        parameters[3] = new int256[](2);
        parameters[3][0] = 2.5e18; // Parameter 4 Exponents
        parameters[3][1] = 3.5e18; // Parameter 4 Exponents
        parameters[4] = new int256[](2);
        parameters[4][0] = 0.8e18; // Parameter 5 Inverse Scaling
        parameters[4][1] = 1e18; // Parameter 5 Inverse Scaling
        parameters[5] = new int256[](2);
        parameters[5][0] = 0.5e18; // Parameter 6 Pre-exp Scaling
        parameters[5][1] = 0.3e18; // Parameter 6 Pre-exp Scaling
        parameters[6] = new int256[](1);
        parameters[6][0] = PRBMathSD59x18.fromInt(0); // Parameter 7 Don't use raw price

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
        
        expectedResults[0] = 0.626952890125817400e18;
        expectedResults[1] = 0.373047109874182800e18;

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
}
