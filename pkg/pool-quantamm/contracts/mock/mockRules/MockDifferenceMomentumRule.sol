// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;
import "../../rules/DifferenceMomentumUpdateRule.sol";

contract MockDifferenceMomentumRule is DifferenceMomentumUpdateRule {
    constructor(address _updateWeightRunner) DifferenceMomentumUpdateRule(_updateWeightRunner) {}

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
        return _quantAMMUnpack128Array(intermediateGradientStates[poolAddress], numAssets);
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
