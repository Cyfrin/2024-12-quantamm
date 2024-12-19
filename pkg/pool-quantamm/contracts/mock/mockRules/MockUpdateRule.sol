
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "../../rules/UpdateRule.sol";

contract MockUpdateRule is UpdateRule {
    constructor(address _updateWeightRunner) UpdateRule(_updateWeightRunner) {}

    int256[] weights;
    int256[] intermediateValues;
    bool validParametersResults;


    function setWeights(int256[] memory _weights) external {
        weights = _weights;
    }

    function GetResultWeights() external view returns (int256[] memory results) {
        return weights;
    }

    function GetMovingAverages(address poolAddress, uint numAssets) external view returns (int256[] memory results) {
        return _quantAMMUnpack128Array(movingAverages[poolAddress], numAssets);
    }

    function validParameters(int256[][] calldata /*_parameters*/) external view override returns (bool) {
        return validParametersResults;
    }

    function _getWeights(
        int256[] calldata /*_prevWeights*/,
        int256[] memory /*_data*/,
        int256[][] calldata /*_parameters*/,
        QuantAMMPoolParameters memory /*_poolParameters*/
    ) internal virtual override returns (int256[] memory newWeights) {
        return weights;
    }

    function _requiresPrevMovingAverage() internal pure virtual override returns (uint16) {
        return 0;
    }

    function _setInitialIntermediateValues(
        address,
        int256[] memory _initialValues,
        uint 
    ) internal virtual override {
        intermediateValues = _initialValues;
    }
}