// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;
import "../../rules/MinimumVarianceUpdateRule.sol";

contract MockMinimumVarianceRule is MinimumVarianceUpdateRule {
    constructor(address _updateWeightRunner) MinimumVarianceUpdateRule(_updateWeightRunner) {}

    int256[] weights;

    function GetResultWeights() external view returns (int256[] memory results) {
        return weights;
    }

    function GetMovingAverages(address poolAddress, uint numAssets) external view returns (int256[] memory results) {
        return _quantAMMUnpack128Array(movingAverages[poolAddress], numAssets);
    }

    function GetIntermediateValues(
        address poolAddress,
        uint numAssets
    ) external view returns (int256[] memory results) {
        return _quantAMMUnpack128Array(intermediateVarianceStates[poolAddress], numAssets);
    }

    function CalculateUnguardedWeights(
        int256[] calldata prevWeights,
        int256[] calldata data,
        address pool,
        int256[][] calldata _parameters,
        int128[] memory lambda,
        int256[] memory _movingAverageData
    ) external {
        QuantAMMPoolParameters memory poolParameters;
        poolParameters.lambda = lambda;
        poolParameters.movingAverage = _movingAverageData;
        poolParameters.pool = pool;

        weights = _getWeights(prevWeights, data, _parameters, poolParameters);
    }
}
