// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IUpdateRule.sol";
import "../rules/base/QuantammBasedRuleHelpers.sol";
import "../rules/base/QuantammCovarianceBasedRule.sol";
import "../rules/base/QuantammGradientBasedRule.sol";
import "../rules/base/QuantammVarianceBasedRule.sol";

contract MockCalculationRule is
    IUpdateRule,
    QuantAMMCovarianceBasedRule,
    QuantAMMGradientBasedRule,
    QuantAMMVarianceBasedRule
{
    int256[] prevMovingAverage;
    int256[] results;
    int256[][] matrixResults;

    function setPrevMovingAverage(int256[] memory _prevMovingAverage) external {
        prevMovingAverage = _prevMovingAverage;
    }

    function getResults() external view returns (int256[] memory) {
        return results;
    }

    function getMatrixResults() external view returns (int256[][] memory) {
        return matrixResults;
    }

    function convert256Array(int256[] memory originalArray) internal pure returns (int128[] memory) {
        int128[] memory finalArray = new int128[](originalArray.length);
        for (uint i; i < originalArray.length; ++i) {
            finalArray[i] = int128(originalArray[i]);
        }
        return finalArray;
    }

    function externalCalculateQuantAMMVariance(
        int256[] calldata _newData,
        int256[] memory _movingAverage,
        address pool,
        int128[] memory _lambda,
        uint numAssets
    ) external {
        QuantAMMPoolParameters memory poolParameters;
        poolParameters.pool = pool;
        poolParameters.numberOfAssets = numAssets;
        poolParameters.lambda = _lambda;
        poolParameters.movingAverage = _movingAverage;

        results = convert256Array(_calculateQuantAMMVariance(_newData, poolParameters));
    }

    function externalCalculateQuantAMMGradient(
        int256[] calldata _newData,
        int256[] memory _movingAverage,
        address pool,
        int128[] memory lambda,
        uint numAssets
    ) external {
        QuantAMMPoolParameters memory poolParameters;
        poolParameters.pool = pool;
        poolParameters.numberOfAssets = numAssets;
        poolParameters.lambda = lambda;
        poolParameters.movingAverage = _movingAverage;

        int256[] memory calcResults = _calculateQuantAMMGradient(_newData, poolParameters);

        results = calcResults;
    }

    function externalCalculateQuantAMMCovariance(
        int256[] calldata _newData,
        int256[] memory _movingAverage,
        address pool,
        int128[] memory _lambda,
        uint numAssets
    ) external {
        QuantAMMPoolParameters memory poolParameters;
        poolParameters.pool = pool;
        poolParameters.numberOfAssets = numAssets;
        poolParameters.lambda = _lambda;
        poolParameters.movingAverage = _movingAverage;

        matrixResults = _calculateQuantAMMCovariance(_newData, poolParameters);
    }

    function setInitialGradient(address poolAddress, int256[] memory _initialValues, uint _numberOfAssets) external {
        _setGradient(poolAddress, _initialValues, _numberOfAssets);
    }

    function setInitialVariance(address poolAddress, int256[] memory _initialValues, uint _numberOfAssets) external {
        _setIntermediateVariance(poolAddress, _initialValues, _numberOfAssets);
    }

    function setInitialCovariance(
        address poolAddress,
        int256[][] memory _initialValues,
        uint _numberOfAssets
    ) external {
        _setIntermediateCovariance(poolAddress, _initialValues, _numberOfAssets);
    }

    function CalculateNewWeights(
        int256[] calldata prevWeights,
        int256[] calldata data,
        address pool,
        int256[][] calldata _parameters,
        uint64[] calldata lambdaStore,
        uint64 epsilonMax,
        uint64 absoluteWeightGuardRail
    ) external override returns (int256[] memory updatedWeights) {}

    function initialisePoolRuleIntermediateValues(
        address poolAddress,
        int256[] memory _newMovingAverages,
        int256[] memory _newParameters,
        uint _numberOfAssets
    ) external override {}

    /// @notice Check if the given parameters are valid for the rule
    function validParameters(int256[][] calldata parameters) external pure override returns (bool) {}
}
