pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import "../../../contracts/mock/MockRuleInvoker.sol";
import "../../../contracts/mock/mockRules/MockMinimumVarianceRule.sol";
import "../../../contracts/mock/MockPool.sol";
import "../utils.t.sol";

contract MinVarianceUpdateRuleTest is Test, QuantAMMTestUtils {
    MockMinimumVarianceRule rule;
    MockPool mockPool;

    function setUp() public {
        // Deploy Power Channel Rule contract
        rule = new MockMinimumVarianceRule(address(this));

        // Deploy Mock Pool contract
        mockPool = new MockPool(3600, PRBMathSD59x18.fromInt(1), address(rule));
    }

    function testEmptyParametersShouldNotBeAccepted() public view {
        int256[][] memory parameters; // Empty parameters
        bool valid = rule.validParameters(parameters); // Call the function
        assertFalse(valid); // Assert that the result is false
    }

    function testZeroShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(0); // 0 should be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, true); // Assert that the result is true
    }

    function testNumberBetweenZeroAndOneShouldBeAccepted() public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = 0.75e18; // 0.75 should be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, true); // Assert that the result is true
    }

    function testFuzz_NumberBetweenZeroAndOneShouldBeAccepted(int256 param) public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = bound(param, 1, 0.9999999999999999e18); // 0.75 should be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, true); // Assert that the result is true
    }

    function testNumberGreaterThanOneShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(2); // 2 should not be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, false); // Assert that the result is false
    }

    function testFuzz_NumberGreaterThanOneShouldNotBeAccepted(int256 param) public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(bound(param, 1e18, maxScaledFixedPoint18())); // 2 should not be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, false); // Assert that the result is false
    }

    function testNumberLessThanZeroShouldNotBeAccepted() public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = -PRBMathSD59x18.fromInt(1); // -1 should not be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, false); // Assert that the result is false
    }

    function testFuzz_NumberLessThanZeroShouldNotBeAccepted(int256 param) public view {
        int256[][] memory parameters = new int256[][](1); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = -PRBMathSD59x18.fromInt(bound(param, 1, maxScaledFixedPoint18())); // -1 should not be accepted

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, false); // Assert that the result is false
    }

    function testAdditionalParametersShouldBeRejected() public view {
        int256[][] memory parameters = new int256[][](2); // Additional parameters
        parameters[0] = new int256[](1);
        parameters[0][0] = PRBMathSD59x18.fromInt(0);
        parameters[1] = new int256[](1);
        parameters[1][0] = PRBMathSD59x18.fromInt(0); // Additional parameters

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, false); // Assert that the result is false
    }

    function testFuzz_AdditionalParametersShouldBeRejected(
        uint256 paramLength,
        uint256 innerLength,
        int256 defaultParam
    ) public view {
        uint256 totalParams = bound(paramLength, 2, 10);
        uint256 innerParams = bound(innerLength, 2, 10);
        int256[][] memory parameters = new int256[][](totalParams); // Additional parameters
        for (uint256 i = 0; i < totalParams; i++) {
            parameters[i] = new int256[](innerParams);
            for (uint256 j = 0; j < innerParams; j++) {
                parameters[i][j] = PRBMathSD59x18.fromInt(
                    bound(defaultParam, minScaledFixedPoint18(), maxScaledFixedPoint18())
                );
            }
        }

        bool result = rule.validParameters(parameters); // Call the function
        assertEq(result, false); // Assert that the result is false
    }

    function testCorrectUpdateWithLambdaPointFiveAndTwoWeights() public {
        // Set the number of assets to 2
        mockPool.setNumberOfAssets(2);

        // Define parameters and inputs
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        parameters[0][0] = 0.5e18;

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory variances = new int256[](2);
        variances[0] = PRBMathSD59x18.fromInt(1);
        variances[1] = PRBMathSD59x18.fromInt(1);

        int256[] memory prevMovingAverages = new int256[](4);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        prevMovingAverages[2] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[3] = PRBMathSD59x18.fromInt(1) + 0.5e18;

        int128[] memory lambda = new int128[](1);
        lambda[0] = 0.7e18;

        // Initialize pool rule intermediate values
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            variances,
            mockPool.numAssets()
        );

        // Calculate unguarded weights
        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambda, prevMovingAverages);

        // Get and check result weights
        int256[] memory res = rule.GetResultWeights();

        int256[] memory ex = new int256[](2);
        ex[0] = 0.548283261802575107e18;
        ex[1] = 0.451716738197424892e18;

        checkResult(res, ex);
        // Expected result: [0.5482832618025751, 0.4517167381974248]
    }

    function testCorrectUpdateWithLambdaPointNineAndTwoWeights() public {
        // Set the number of assets to 2
        mockPool.setNumberOfAssets(2);

        // Define parameters and inputs
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        parameters[0][0] = 0.9e18;

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory variances = new int256[](2);
        variances[0] = PRBMathSD59x18.fromInt(1);
        variances[1] = PRBMathSD59x18.fromInt(1);

        int256[] memory prevMovingAverages = new int256[](4);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        prevMovingAverages[2] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[3] = PRBMathSD59x18.fromInt(1) + 0.5e18;

        int128[] memory lambda = new int128[](2);
        lambda[0] = 0.7e18;
        lambda[1] = 0.7e18;

        // Initialize pool rule intermediate values
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            variances,
            mockPool.numAssets()
        );

        // Calculate unguarded weights
        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambda, prevMovingAverages);

        // Get and check result weights
        int256[] memory res = rule.GetResultWeights();

        int256[] memory ex = new int256[](2);
        ex[0] = 0.509656652360515021e18;
        ex[1] = 0.490343347639484978e18;

        checkResult(res, ex);
    }

    function testCorrectUpdateWithVectorParameterLambdaPointFiveAndTwoWeights() public {
        // Set the number of assets to 2
        mockPool.setNumberOfAssets(2);

        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](2);
        parameters[0][0] = 0.9e18;
        parameters[0][1] = 0.7e18;

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory variances = new int256[](2);
        variances[0] = PRBMathSD59x18.fromInt(1);
        variances[1] = PRBMathSD59x18.fromInt(1);

        int256[] memory prevMovingAverages = new int256[](4);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        prevMovingAverages[2] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[3] = PRBMathSD59x18.fromInt(1) + 0.5e18;

        int128[] memory lambda = new int128[](2);
        lambda[0] = 0.7e18;
        lambda[1] = 0.7e18;

        // Initialize pool rule intermediate values
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            variances,
            mockPool.numAssets()
        );

        // Calculate unguarded weights
        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambda, prevMovingAverages);

        // Get and check result weights
        int256[] memory res = rule.GetResultWeights();

        int256[] memory ex = new int256[](2);
        ex[0] = 0.509656652360515021e18;
        // The value ex[1] is not exactly correct as it comes from floating point calcs
        // and so needs to be updated after vector parameter functionality is implemented.
        // It should be very close to this current set value, 0.47103004291845496
        ex[1] = 0.471030042918454935e18;

        checkResult(res, ex);
    }

    function testCorrectUpdateWithVectorParameterLambdaPointNineAndTwoWeights() public {
        // Set the number of assets to 2
        mockPool.setNumberOfAssets(2);

        // Define parameters and inputs
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](2);
        parameters[0][0] = 0.9e18;
        parameters[0][1] = 0.7e18;

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory variances = new int256[](2);
        variances[0] = PRBMathSD59x18.fromInt(1);
        variances[1] = PRBMathSD59x18.fromInt(1);

        int256[] memory prevMovingAverages = new int256[](4);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        prevMovingAverages[2] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[3] = PRBMathSD59x18.fromInt(1) + 0.5e18;

        int128[] memory lambda = new int128[](1);
        lambda[0] = 0.7e18;

        // Initialize pool rule intermediate values
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            variances,
            mockPool.numAssets()
        );

        // Calculate unguarded weights
        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambda, prevMovingAverages);

        // Get and check result weights
        int256[] memory res = rule.GetResultWeights();

        int256[] memory ex = new int256[](2);
        ex[0] = 0.509656652360515021e18;
        // The value ex[1] is not exactly correct as it comes from floating point calcs
        // and so needs to be updated after vector parameter functionality is implemented.
        // It should be very close to this current set value, 0.47103004291845496
        ex[1] = 0.471030042918454935e18;

        checkResult(res, ex);
    }

    function testCorrectUpdateWithScalarParameterVectorLambdaTwoWeights() public {
        // Set the number of assets to 2
        mockPool.setNumberOfAssets(2);

        // Define parameters and inputs
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        parameters[0][0] = 0.9e18;

        int256[] memory prevWeights = new int256[](2);
        prevWeights[0] = 0.5e18;
        prevWeights[1] = 0.5e18;

        int256[] memory data = new int256[](2);
        data[0] = PRBMathSD59x18.fromInt(3);
        data[1] = PRBMathSD59x18.fromInt(4);

        int256[] memory variances = new int256[](2);
        variances[0] = PRBMathSD59x18.fromInt(1);
        variances[1] = PRBMathSD59x18.fromInt(1);

        int256[] memory prevMovingAverages = new int256[](4);
        prevMovingAverages[0] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[1] = PRBMathSD59x18.fromInt(1) + 0.5e18;
        prevMovingAverages[2] = PRBMathSD59x18.fromInt(1);
        prevMovingAverages[3] = PRBMathSD59x18.fromInt(1) + 0.5e18;

        int128[] memory lambda = new int128[](2);
        lambda[0] = 0.95e18;
        lambda[1] = 0.5e18;

        // Initialize pool rule intermediate values
        rule.initialisePoolRuleIntermediateValues(
            address(mockPool),
            prevMovingAverages,
            variances,
            mockPool.numAssets()
        );

        // Calculate unguarded weights
        rule.CalculateUnguardedWeights(prevWeights, data, address(mockPool), parameters, lambda, prevMovingAverages);

        // Get and check result weights
        int256[] memory res = rule.GetResultWeights();

        int256[] memory ex = new int256[](2);
        ex[0] = 0.543167701863354037e18;
        ex[1] = 0.456832298136645962e18;

        checkResult(res, ex);
    }
}
