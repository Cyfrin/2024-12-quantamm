// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;
import "../../rules/PowerChannelUpdateRule.sol";

contract MockPowerChannelRule is PowerChannelUpdateRule {
    constructor(address _updateWeightRunner) PowerChannelUpdateRule(_updateWeightRunner) {}

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
        int256[] calldata _prevWeights,
        int256[] calldata _data,
        address _pool,
        int256[][] calldata _parameters,
        int128[] memory _lambda,
        int256[] memory _movingAverageData
    ) external {
        QuantAMMPoolParameters memory poolParameters;
        poolParameters.lambda = _lambda;
        poolParameters.movingAverage = _movingAverageData;
        poolParameters.pool = _pool;

        weights = _getWeights(_prevWeights, _data, _parameters, poolParameters);
    }
}
