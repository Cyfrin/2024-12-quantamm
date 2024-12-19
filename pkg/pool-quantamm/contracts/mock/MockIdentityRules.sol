// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IUpdateRule.sol";
import "../rules/UpdateRule.sol";
import "../UpdateWeightRunner.sol";

/// @notice Rule that simply returns the previous weights for testing
contract MockIdentityRule is IUpdateRule {
    /// @notice Flags to control in tests which data should be pulled
    bool queryGradient;

    bool queryCovariances;

    bool queryPrecision;

    bool queryVariances;

    bool public CalculateNewWeightsCalled;

    int256[] public movingAverages;

    int256[] public intermediateValues;

    uint public numberOfAssets;

    int256[] weights;

    function getWeights() external view returns (int256[] memory){
        return weights;
    }

    function getMovingAverages() external view returns (int256[] memory) {
        return movingAverages;
    }

    function getIntermediateValues() external view returns (int256[] memory) {
        return intermediateValues;
    }

    function CalculateNewWeights(
        int256[] calldata prevWeights,
        int256[] calldata /*data*/,
        address /*pool*/,
        int256[][] calldata /*_parameters*/,
        uint64[] calldata /*lambdaStore*/,
        uint64 /*epsilonMax*/,
        uint64 /* absoluteWeightGuardRail*/
    ) external override returns (int256[] memory /*updatedWeights*/) {
        CalculateNewWeightsCalled = true;
        if(weights.length == 0) {
            return new int256[](prevWeights.length);
        }
        return weights;
    }

    function initialisePoolRuleIntermediateValues(
        address /*pool*/,
        int256[] memory _newMovingAverages,
        int256[] memory _newParameters,
        uint _numberOfAssets
    ) external override {
        movingAverages = _newMovingAverages;
        intermediateValues = _newParameters;
        numberOfAssets = _numberOfAssets;
    }

    /// @notice Check if the given parameters are valid for the rule
    function validParameters(int256[][] calldata /*parameters*/) external pure override returns (bool) {
        return true;
    }

    function SetCalculateNewWeightsCalled(bool newVal) external {
        CalculateNewWeightsCalled = newVal;
    }

    function setQueryGradient(bool _queryGradient) public {
        queryGradient = _queryGradient;
    }

    function setQueryCovariances(bool _queryCovariances) public {
        queryCovariances = _queryCovariances;
    }

    function setQueryPrecision(bool _queryPrecision) public {
        queryPrecision = _queryPrecision;
    }

    function setQueryVariances(bool _queryVariances) public {
        queryVariances = _queryVariances;
    }

    function setWeights(int256[] memory newCalculatedWeights) public {
        weights = newCalculatedWeights;
    }
}
