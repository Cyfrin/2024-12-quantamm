//SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title The implementations required for a new update rule to run on robodex
interface IUpdateRule {
    /// @param _prevWeights the weights at the current block time
    /// @param _data the data from the oracles called in getdata in update weight runner
    /// @param _pool the pool address
    /// @param _parameters any parameters required by the rule apart from lambda
    /// @param _lambdaStore lambda values either 1 for all constituents or one per constituent
    /// @param _epsilonMax the maximum trade size possible for the pool
    /// @param _absoluteWeightGuardRail the maximum weight change possible for the pool
    function CalculateNewWeights(
        int256[] calldata _prevWeights,
        int256[]  memory _data,
        address _pool,
        int256[][] calldata _parameters,
        uint64[] calldata _lambdaStore,
        uint64 _epsilonMax,
        uint64 _absoluteWeightGuardRail
    ) external returns (int256[] memory updatedWeights);

    /// @notice Called on pool creation to preset all the neccessary rule state
    /// @param _poolAddress address of pool being initialised
    /// @param _newIntermediateValues array of initial intermediate values values
    /// @param _newParameters array of initial parameters, dynamic to allow flexibility for future rules
    /// @param _numberOfAssets number of assets in the pool
    function initialisePoolRuleIntermediateValues(
        address _poolAddress,
        int256[] memory _newIntermediateValues,
        int256[] memory _newParameters,
        uint _numberOfAssets
    ) external;

    /// @notice Check if the given parameters are valid for the rule
    /// @param _parameters the parameters to check
    function validParameters(int256[][] calldata _parameters) external view returns (bool);
}
