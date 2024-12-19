// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./base/QuantammVarianceBasedRule.sol";
import "./UpdateRule.sol";

/// @title MinimumVarianceUpdateRule contract for QuantAMM minimum variance update rule
/// @notice Contains the logic for calculating the new weights of a QuantAMM pool using the minimum variance update rule and updating the weights of the QuantAMM pool
contract MinimumVarianceUpdateRule is QuantAMMVarianceBasedRule, UpdateRule {
    constructor(address _updateWeightRunner) UpdateRule(_updateWeightRunner) {
        name = "MinimumVariance";

        parameterDescriptions = new string[](1);
        parameterDescriptions[0] = unicode"Mixing Lambda (Λ): Mixing Lambda controls how the weight smoothing is done.";
    }

    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    //this is a property of the rule so can be constant. Used in moving average storage decision
    uint16 private constant REQUIRES_PREV_MAVG = 1;

    /// @param _prevWeights the previous weights retrieved from the vault
    /// @param _data the latest data from the signal, usually price
    /// @param _parameters the parameters of the rule that are not lambda
    /// @param _poolParameters pool parameters [0]=Λ
    /// @notice w(t) = (Λ * w(t − 1)) + ((1 − Λ)*Σ^−1(t)) / N,j=1∑ Σ^−1 j(t) - see whitepaper
    function _getWeights(
        int256[] calldata _prevWeights,
        int256[]  memory _data,
        int256[][] calldata _parameters, //
        QuantAMMPoolParameters memory _poolParameters
    ) internal override returns (int256[] memory newWeightsConverted) {
        _poolParameters.numberOfAssets = _prevWeights.length;

        //reuse of the newWeights array allows for saved gas in array initialisation
        int256[] memory newWeights = _calculateQuantAMMVariance(_data, _poolParameters);

        int256 divisionFactor;
        newWeightsConverted = new int256[](_prevWeights.length);

        if (_parameters[0].length == 1) {
            int256 mixingVariance = _parameters[0][0];
            // calculating (1 − Λ)*Σ^−1(t)
            int256 oneMinusLambda = ONE - mixingVariance;
            for (uint i; i < _prevWeights.length; ) {
                int256 precision = ONE.div(newWeights[i]);
                divisionFactor += precision;
                newWeights[i] = oneMinusLambda.mul(precision);
                unchecked {
                    ++i;
                }
            }
            // To avoid intermediate overflows (because of normalization), we only downcast in the end to an uint64
            // Divide precision vector by the sum of precisions and add Λw(t - 1)
            // (Λ * w(t − 1)) + ((1 − Λ)*Σ^−1(t)) / N,j=1∑ Σ^−1 j(t)
            for (uint i; i < _prevWeights.length; ) {
                int256 res = mixingVariance.mul(int256(_prevWeights[i])) + newWeights[i].div(divisionFactor);
                newWeightsConverted[i] = res;
                unchecked {
                    ++i;
                }
            }
        } else {
            // calculating (1 − Λ)*Σ^−1(t)
            for (uint i; i < _prevWeights.length; ) {
                int256 mixingVariance = _parameters[0][i];
                int256 oneMinusLambda = ONE - mixingVariance;
                int256 precision = ONE.div(newWeights[i]);
                divisionFactor += precision;
                newWeights[i] = oneMinusLambda.mul(precision);
                unchecked {
                    ++i;
                }
            }
            // To avoid intermediate overflows (because of normalization), we only downcast in the end to an uint64
            // Divide precision vector by the sum of precisions and add Λw(t - 1)
            // (Λ * w(t − 1)) + ((1 − Λ)*Σ^−1(t)) / N,j=1∑ Σ^−1 j(t)
            for (uint i; i < _prevWeights.length; ) {
                int256 mixingVariance = _parameters[0][i];
                int256 res = mixingVariance.mul(int256(_prevWeights[i])) + newWeights[i].div(divisionFactor);
                newWeightsConverted[i] = res;
                unchecked {
                    ++i;
                }
            }
        }

        return newWeightsConverted;
    }

    /// @notice Set the initial intermediate values for the rule
    /// @param _poolAddress target pool address
    /// @param _initialValues initial values of intermediate state
    /// @param _numberOfAssets number of assets in the pool
    function _setInitialIntermediateValues(
        address _poolAddress,
        int256[] memory _initialValues,
        uint _numberOfAssets
    ) internal override {
        _setIntermediateVariance(_poolAddress, _initialValues, _numberOfAssets);
    }

    /// @notice Wether the rule requires the previous moving average
    /// @return 1 if the rule requires the previous moving average, 0 otherwise
    function _requiresPrevMovingAverage() internal pure override returns (uint16) {
        return REQUIRES_PREV_MAVG;
    }

    /// @notice Check if the given parameters are valid for the rule
    /// @param _parameters the parameters of the rule, in this case the mixing variance
    /// @dev If parameters are not valid, either reverts or returns false
    function validParameters(int256[][] calldata _parameters) external pure override returns (bool) {
        if (_parameters.length == 1 && _parameters[0].length >= 1) {
            for (uint i; i < _parameters[0].length; ) {
                if (_parameters[0][i] < 0 || _parameters[0][i] > ONE) {
                    return false;
                }
                unchecked {
                    ++i;
                }
            }
            return true;
        }
        return false;
    }
}
