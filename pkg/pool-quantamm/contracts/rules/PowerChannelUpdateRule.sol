// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./base/QuantammGradientBasedRule.sol";
import "./UpdateRule.sol";

/// @title PowerChannelUpdateRule contract for QuantAMM power channel update rule
/// @notice Contains the logic for calculating the new weights of a QuantAMM pool using the power channel update rule
contract PowerChannelUpdateRule is QuantAMMGradientBasedRule, UpdateRule {
    constructor(address _updateWeightRunner) UpdateRule(_updateWeightRunner) {
        name = "PowerChannel";

        parameterDescriptions = new string[](4);
        parameterDescriptions[0] = "Kappa: Kappa dictates the aggressiveness of response to a signal change";
        parameterDescriptions[1] = "Q: Q dictates the harshness of the channel boundry";
        parameterDescriptions[2] = "Use raw price: 0 = use moving average, 1 = use raw price to be used as the denominator";
        parameterDescriptions[3] = "Lambda: Lambda dictates the estimator weighting and price smoothing for a given period of time";
    }

    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    uint16 private constant REQUIRES_PREV_MAVG = 0;

    /// @dev struct to avoid stack too deep issues
    /// @notice Struct to store local variables for the power channel calculation
    /// @param kappa array of kappa value parameters
    /// @param newWeights array of new weights
    /// @param normalizationFactor normalization factor for the weights
    /// @param prevWeightsLength length of the previous weights
    /// @param useRawPrice boolean to determine if raw price should be used or average
    /// @param i index for looping
    /// @param q Q value
    /// @param denominator denominator for the weights
    /// @param sumKappa sum of all kappa values
    /// @param res result of the calculation
    /// @param sign sign of the calculation
    /// @param intermediateRes intermediate result of the calculation
    struct QuantAMMPowerChannelLocals {
        int256[] kappa;
        int256[] newWeights;
        int256 normalizationFactor;
        uint256 prevWeightsLength;
        bool useRawPrice;
        uint i;
        int256 q;
        int256[] vectorQ;
        int256 denominator;
        int256 sumKappa;
        int256 res;
        int256 sign;
        int256 intermediateRes;
    }

    /// @notice w(t) = w(t − 1) + κ · ( sign(1/p(t)*∂p(t)/∂t) * |1/p(t)*∂p(t)/∂t|^q − ℓp(t) ) where ℓp(t) = 1/N * ∑(sign(1/p(t)*∂p(t)/∂t) * |1/p(t)*∂p(t)/∂t|^q)
    /// @param _prevWeights the previous weights retrieved from the vault
    /// @param _data the latest data from the signal, usually price
    /// @param _parameters the parameters of the rule that are not lambda
    /// @param _poolParameters pool parameters [0]=k, [1]=q, can be per token (vector) or single for all tokens (scalar), [2]=useRawPrice
    function _getWeights(
        int256[] calldata _prevWeights,
        int256[]  memory _data,
        int256[][] calldata _parameters, 
        QuantAMMPoolParameters memory _poolParameters
    ) internal override returns (int256[] memory newWeightsConverted) {
        QuantAMMPowerChannelLocals memory locals;
        locals.prevWeightsLength = _prevWeights.length;

        _poolParameters.numberOfAssets = _prevWeights.length;
        // reuse of the newWeights array allows for saved gas in array initialisation
        locals.newWeights = _calculateQuantAMMGradient(_data, _poolParameters);

        locals.kappa = _parameters[0];

        locals.useRawPrice = false;

        // the third parameter determines if power channel should use the price or the average price as the denominator
        if (_parameters.length > 2) {
            locals.useRawPrice = _parameters[2][0] == ONE;
        }

        bool scalarQ = _parameters[1].length == 1;
        locals.q = _parameters[1][0];
        
        for (locals.i = 0; locals.i < locals.prevWeightsLength; ) {
            locals.denominator = _poolParameters.movingAverage[locals.i];
            if(!scalarQ){
                locals.q = _parameters[1][locals.i];
            }

            if (locals.useRawPrice) {
                locals.denominator = _data[locals.i];
            }

            locals.intermediateRes = ONE.div(locals.denominator).mul(locals.newWeights[locals.i]);

            unchecked {
                locals.sign = locals.intermediateRes >= 0 ? ONE : -ONE;
            }
            //sign(1/p(t)*∂p(t)/∂t) * |1/p(t)*∂p(t)/∂t|^q
            //stored as it is used in multiple places, saves on recalculation gas. _pow is quite expensive
            locals.newWeights[locals.i] = locals.sign.mul(_pow(locals.intermediateRes.abs(), locals.q));

            if (locals.kappa.length == 1) {
                locals.normalizationFactor += locals.newWeights[locals.i];
            } else {
                locals.normalizationFactor += locals.kappa[locals.i].mul(locals.newWeights[locals.i]);
            }

            unchecked {
                ++locals.i;
            }
        }

        // To avoid intermediate overflows (because of normalization), we only downcast in the end to an uint64
        newWeightsConverted = new int256[](locals.prevWeightsLength);

        if (locals.kappa.length == 1) {
            locals.normalizationFactor /= int256(locals.prevWeightsLength);

            for (locals.i = 0; locals.i < locals.prevWeightsLength; ) {
                //κ · ( sign(1/p(t)*∂p(t)/∂t) * |1/p(t)*∂p(t)/∂t|^q − ℓp(t)
                locals.res =
                    int256(_prevWeights[locals.i]) +
                    locals.kappa[0].mul(locals.newWeights[locals.i] - locals.normalizationFactor);
                newWeightsConverted[locals.i] = locals.res;
                unchecked {
                    ++locals.i;
                }
            }
        } else {
            //vector parameter calculation, same as scalar but using the per constituent param inside the loops
            int256 sumKappa;
            for (locals.i = 0; locals.i < locals.kappa.length; ) {
                sumKappa += locals.kappa[locals.i];
                unchecked {
                    ++locals.i;
                }
            }

            locals.normalizationFactor = locals.normalizationFactor.div(sumKappa);

            for (locals.i = 0; locals.i < _prevWeights.length; ) {
                //κ · ( sign(1/p(t)*∂p(t)/∂t) * |1/p(t)*∂p(t)/∂t|^q − ℓp(t)
                locals.res =
                    int256(_prevWeights[locals.i]) +
                    locals.kappa[locals.i].mul(locals.newWeights[locals.i] - locals.normalizationFactor);
                require(locals.res >= 0, "Invalid weight");
                newWeightsConverted[locals.i] = locals.res;
                unchecked {
                    ++locals.i;
                }
            }
        }
        return newWeightsConverted;
    }

    /// @notice Get the number of assets required for the rule
    function _requiresPrevMovingAverage() internal pure override returns (uint16) {
        return REQUIRES_PREV_MAVG;
    }

    /// @notice Set the initial intermediate values for the rule, in this case the gradient
    /// @param _poolAddress address of pool being initialised
    /// @param _initialValues the initial intermediate values provided
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
    function validParameters(int256[][] calldata parameters) external pure override returns (bool valid) {
        if (
            (parameters.length == 2 || (parameters.length == 3 && parameters[2].length == 1)) &&
            (parameters[0].length > 0) &&
            (parameters[0].length == 1 && parameters[1].length == 1 
            || parameters[1].length == parameters[0].length)
        ) {
            valid = true;
            for (uint i; i < parameters[0].length; ) {
                if (!(parameters[0][i] > 0)) {
                    valid = false;
                    break;
                }
                unchecked {
                    ++i;
                }
            }

            for (uint i; i < parameters[1].length; ) {
                if(parameters[1][i] <= ONE){
                    valid = false;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            return valid;   
        }
        return false;
    }
}
