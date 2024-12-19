// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./base/QuantammGradientBasedRule.sol";
import "./base/QuantammMathGuard.sol";
import "./base/QuantammMathMovingAverage.sol";
import "./UpdateRule.sol";

/// @title AntiMomentumUpdateRule contract for QuantAMM anti-momentum update rule implementation
/// @notice Contains the logic for calculating the anti-momentum update rule and updating the weights of the QuantAMM pool
contract AntiMomentumUpdateRule is QuantAMMGradientBasedRule, UpdateRule {
    constructor(address _updateWeightRunner) UpdateRule(_updateWeightRunner) {
        name = "AntiMomentum";
        
        parameterDescriptions = new string[](3);
        parameterDescriptions[0] = "Kappa: Kappa dictates the aggressiveness of the rule's response to a signal change (here, -(price gradient))";
        parameterDescriptions[1] = "Use raw price: 0 = use moving average, 1 = use raw price to be used as the denominator";
        parameterDescriptions[2] = "Lambda: Lambda dictates the estimator weighting and price smoothing for a given period of time";
    }

    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    uint16 private constant REQUIRES_PREV_MAVG = 0;

    /// @dev struct to avoid stack too deep issues
    /// @notice Struct to store local variables for the anti-momentum calculation
    /// @param kappa array of kappa value parameters
    /// @param newWeights array of new weights
    /// @param normalizationFactor normalization factor for the weights
    /// @param useRawPrice boolean to determine if raw price should be used or average
    /// @param i index for looping
    /// @param denominator denominator for the weights
    /// @param sumKappa sum of all kappa values
    /// @param res result of the calculation
    struct QuantAMMAntiMomentumLocals {
        int256[] kappa;
        int256[] newWeights;
        int256 normalizationFactor;
        bool useRawPrice;
        uint i;
        int256 denominator;
        int256 sumKappa;
        int256 res;
    }

    /// @param _prevWeights the previous weights retrieved from the vault
    /// @param _data the latest data from the signal, usually price
    /// @param _parameters the parameters of the rule that are not lambda
    /// @param _poolParameters pool parameters [0]=kappa can be per token (vector) or single for all tokens (scalar), [1][0]=useRawPrice
    /// @notice w(t) = w(t − 1) + κ ·(ℓp(t) − 1/p(t) · ∂p(t)/∂t) where ℓp(t) = 1/N * ∑(1/p(t)i * (∂p(t)/∂t)i)
    function _getWeights(
        int256[] calldata _prevWeights,
        int256[]  memory _data,
        int256[][] calldata _parameters,
        QuantAMMPoolParameters memory _poolParameters
    ) internal override returns (int256[] memory newWeightsConverted) {
        QuantAMMAntiMomentumLocals memory locals;
        locals.kappa = _parameters[0];
        locals.useRawPrice = false;

        // the second parameter determines if antimomentum should use the price or the average price as the denominator
        // using the average price has shown greater performance and resilience due to greater smoothing
        if (_parameters.length > 1) {
            locals.useRawPrice = _parameters[1][0] == ONE;
        }

        _poolParameters.numberOfAssets = _prevWeights.length;

        locals.newWeights = _calculateQuantAMMGradient(_data, _poolParameters);

        for (locals.i = 0; locals.i < _prevWeights.length; ) {
            locals.denominator = _poolParameters.movingAverage[locals.i];
            if (locals.useRawPrice) {
                locals.denominator = _data[locals.i];
            }

            //1/p(t) · ∂p(t)/∂t used in both the main part of the equation and normalisation so saved to save gas
            // used of new weights array allows reuse and saved gas
            locals.newWeights[locals.i] = ONE.div(locals.denominator).mul(int256(locals.newWeights[locals.i]));
            if (locals.kappa.length == 1) {
                locals.normalizationFactor += locals.newWeights[locals.i];
            } else {
                locals.normalizationFactor += (locals.newWeights[locals.i].mul(locals.kappa[locals.i]));
            }
            unchecked {
                ++locals.i;
            }
        }

        // To avoid intermediate overflows (because of normalization), we only downcast in the end to an uint64
        newWeightsConverted = new int256[](_prevWeights.length);
        if (locals.kappa.length == 1) {
            locals.normalizationFactor /= int256(_prevWeights.length);
            // w(t − 1) + κ ·(ℓp(t) − 1/p(t) · ∂p(t)/∂t)

            for (locals.i = 0; locals.i < _prevWeights.length; ) {
                int256 res = int256(_prevWeights[locals.i]) +
                    int256(locals.kappa[0]).mul(locals.normalizationFactor - locals.newWeights[locals.i]);
                newWeightsConverted[locals.i] = res;
                unchecked {
                    ++locals.i;
                }
            }
        } else {
            for (locals.i = 0; locals.i < locals.kappa.length; ) {
                locals.sumKappa += locals.kappa[locals.i];
                unchecked {
                    ++locals.i;
                }
            }

            locals.normalizationFactor = locals.normalizationFactor.div(locals.sumKappa);
            
            for (locals.i = 0; locals.i < _prevWeights.length; ) {
                // w(t − 1) + κ ·(ℓp(t) − 1/p(t) · ∂p(t)/∂t)
                int256 res = int256(_prevWeights[locals.i]) +
                    int256(locals.kappa[locals.i]).mul(locals.normalizationFactor - locals.newWeights[locals.i]);
                require(res >= 0, "Invalid weight");
                newWeightsConverted[locals.i] = res;
                unchecked {
                    ++locals.i;
                }
            }
        }

        return newWeightsConverted;
    }

    function _requiresPrevMovingAverage() internal pure override returns (uint16) {
        return REQUIRES_PREV_MAVG;
    }

    /// @param _poolAddress address of pool being initialised
    /// @param _initialValues array of initial gradient values
    /// @param _numberOfAssets number of assets in the pool
    function _setInitialIntermediateValues(
        address _poolAddress,
        int256[] memory _initialValues,
        uint _numberOfAssets
    ) internal override {
        _setGradient(_poolAddress, _initialValues, _numberOfAssets);
    }

    /// @notice Check if the given parameters are valid for the rule
    /// @dev If parameters are not valid, either reverts or returns false
    function validParameters(int256[][] calldata _parameters) external pure override returns (bool) {
        if (_parameters.length == 1 || (_parameters.length == 2 && _parameters[1].length == 1)) {
            int256[] memory kappa = _parameters[0];
            uint16 valid = uint16(kappa.length) > 0 ? 1 : 0;
            for (uint i; i < kappa.length; ) {
                if (!(kappa[i] > 0)) {
                    valid = 0;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            return valid == 1;
        }
        return false;
    }
}
