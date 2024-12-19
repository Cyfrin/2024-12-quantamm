// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./base/QuantammGradientBasedRule.sol";
import "./base/QuantammMathGuard.sol";
import "./base/QuantammMathMovingAverage.sol";
import "./UpdateRule.sol";

/// @title ChannelFollowingUpdateRule contract for QuantAMM channel following weight updates
/// @notice Contains the logic for calculating the new weights of a QuantAMM pool using the channel following strategy
contract ChannelFollowingUpdateRule is QuantAMMGradientBasedRule, UpdateRule {
    constructor(address _updateWeightRunner) UpdateRule(_updateWeightRunner) {
        name = "ChannelFollowing";

        parameterDescriptions = new string[](7);
        parameterDescriptions[0] = "Kappa: Kappa dictates the aggressiveness of response to a signal change.";
        parameterDescriptions[1] = "Width: Width parameter for the mean reversion channel.";
        parameterDescriptions[2] = "Amplitude: Amplitude of the mean reversion effect.";
        parameterDescriptions[3] = "Exponents: Exponents for the trend following portion.";
        parameterDescriptions[4] = "Inverse Scaling: Scaling factor for channel portion. "
            "If set to max(exp(-x^2/2)sin(pi*x/3)) [=0.541519...] "
            "then the amplitude parameter directly controls the channel height.";
        parameterDescriptions[5] = "Pre-exp Scaling: Scaling factor before exponentiation in the trend following portion.";
        parameterDescriptions[6] = "Use raw price: 0 = use moving average, 1 = use raw price for denominator of price gradient.";
    }

    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1e18;
    int256 private constant TWO = 2e18;
    int256 private constant THREE = 3e18;
    int256 private constant SIX = 6e18;
    int256 private constant PI = 3.141592653589793238e18; // π scaled to 18 decimals
    uint16 private constant REQUIRES_PREV_MAVG = 0;

    /// @dev struct to avoid stack too deep issues
    /// @notice Struct to store local variables for the channel following calculation
    /// @param kappa array of kappa value parameters
    /// @param width array of width value parameters
    /// @param amplitude array of amplitude value parameters
    /// @param exponents array of exponent value parameters
    /// @param inverseScaling array of inverse scaling value parameters
    /// @param preExpScaling array of pre-exp scaling value parameters
    /// @param newWeights array of new weights
    /// @param signal array of signal values
    /// @param normalizationFactor normalization factor for the weights
    /// @param prevWeightLength length of the previous weights
    /// @param useRawPrice boolean to determine if raw price should be used or average
    /// @param i index for looping
    /// @param denominator denominator for the weights
    /// @param sumKappa sum of all kappa values
    struct ChannelFollowingLocals {
        int256[] kappa;
        int256[] width;
        int256[] amplitude;
        int256[] exponents;
        int256[] inverseScaling;
        int256[] preExpScaling;
        int256[] newWeights;
        int256[] signal;
        int256 normalizationFactor;
        uint256 prevWeightLength;
        bool useRawPrice;
        uint i;
        int256 denominator;
        int256 sumKappa;
    }

    /// @notice Calculates the new weights for a QuantAMM pool using the channel following strategy.
    /// @notice The channel following strategy combines trend following with a channel component:
    /// w(t) = w(t-1) + κ[channel + trend - normalizationFactor]
    /// where:
    /// - g = normalized price gradient = (1/p)·(dp/dt)
    /// - envelope = exp(-g²/(2W²))
    /// - s = pi * g / (3W)
    /// - channel = -(A/h)·envelope · (s - 1/6 s^3)
    /// - trend = (1-envelope) * sign(g) * |g/(2S)|^(exponent)
    /// - normalizationFactor = 1/N * ∑(κ[channel + trend])_i
    /// Parameters:
    /// - κ: Kappa controls overall update magnitude
    /// - W: Width controls the channel and envelope width
    /// - A: Amplitude controls channel height
    /// - exponents: Exponent for the trend following portion
    /// - h: Inverse scaling within the channel
    /// - S: Pre-exp scaling for trend component
    /// The strategy aims to:
    /// 1. Mean-revert within the channel (channel component, for small changes in g)
    /// 2. Follow trends (nonlinearly, if exponents are not 1) outside the channel (trend component, for large changes in g)
    /// 3. Smoothly transition between the two regimes (via the envelope function)
    /// @param _prevWeights the previous weights retrieved from the vault
    /// @param _data the latest data, usually price
    /// @param _parameters the parameters of the rule that are not lambda.
    ///     Parameters [0] through [5] are arrays/vectors, [6] is a scalar.
    ///     [0]=kappa
    ///     [1]=width
    ///     [2]=amplitude
    ///     [3]=exponents
    ///     [4]=inverseScaling
    ///     [5]=preExpScaling
    ///     [6]=useRawPrice
    function _getWeights(
        int256[] calldata _prevWeights,
        int256[] memory _data,
        int256[][] calldata _parameters,
        QuantAMMPoolParameters memory _poolParameters
    ) internal override returns (int256[] memory newWeightsConverted) {
        ChannelFollowingLocals memory locals;

        locals.kappa = _parameters[0];
        locals.width = _parameters[1];
        locals.amplitude = _parameters[2];
        locals.exponents = _parameters[3];
        locals.inverseScaling = _parameters[4];
        locals.preExpScaling = _parameters[5];

        _poolParameters.numberOfAssets = _prevWeights.length;
        locals.prevWeightLength = _prevWeights.length;

        // the 7th parameter to determine if momentum should use the price or the average price as the denominator
        // using the average price has shown greater performance and resilience due to greater smoothing
        locals.useRawPrice = _parameters[6][0] == ONE;

        // Calculate price gradients
        locals.newWeights = _calculateQuantAMMGradient(_data, _poolParameters);

        for (locals.i = 0; locals.i < locals.prevWeightLength; ) {
            locals.denominator = _poolParameters.movingAverage[locals.i];
            if (locals.useRawPrice) {
                locals.denominator = _data[locals.i];
            }

            // 1/p(t) * ∂p(t)/∂t calculated and stored as used in multiple places
            locals.newWeights[locals.i] = ONE.div(locals.denominator).mul(locals.newWeights[locals.i]);

            unchecked {
                ++locals.i;
            }
        }
        locals.signal = new int256[](locals.prevWeightLength);

        // Calculate signal for each asset
        for (locals.i = 0; locals.i < locals.prevWeightLength; ) {
            // Calculate envelope: exp(-(price_gradient^2) / (2 * width^2))
            int256 gradientSquared = locals.newWeights[locals.i].mul(locals.newWeights[locals.i]);
            int256 trendPortion;
            int256 channelPortion;
            int256 envelope_exponent;
            int256 envelope;
            if (locals.kappa.length == 1) {
                int256 widthSquared = locals.width[0].mul(locals.width[0]);
                envelope_exponent = -gradientSquared.div(widthSquared.mul(TWO));
                envelope = envelope_exponent.exp();

                // Calculate scaled price gradient: π * price_gradient / (3 * width)
                int256 scaledGradient = PI.mul(locals.newWeights[locals.i]).div(locals.width[0].mul(THREE));
                
                // Calculate channel portion
                channelPortion = locals
                    .amplitude[0]
                    .mul(envelope)
                    .mul(scaledGradient - scaledGradient.mul(scaledGradient).mul(scaledGradient).div(SIX))
                    .div(locals.inverseScaling[0]);
                
                // Calculate trend portion
                int256 absGradient = locals.newWeights[locals.i] >= 0
                    ? locals.newWeights[locals.i]
                    : -locals.newWeights[locals.i];
                
                int256 scaledAbsGradient = absGradient.div(locals.preExpScaling[0].mul(TWO));
                
                trendPortion = _pow(scaledAbsGradient, locals.exponents[0]);
            } else {
                int256 widthSquared = locals.width[locals.i].mul(locals.width[locals.i]);
                envelope = (-gradientSquared.div(widthSquared.mul(TWO))).exp();
                // Calculate scaled price gradient: π * price_gradient / (3 * width)
                int256 scaledGradient = PI.mul(locals.newWeights[locals.i]).div(locals.width[locals.i].mul(THREE));

                // Calculate channel portion
                channelPortion = locals
                    .amplitude[locals.i]
                    .mul(envelope)
                    .mul(scaledGradient - scaledGradient.mul(scaledGradient).mul(scaledGradient).div(SIX))
                    .div(locals.inverseScaling[locals.i]);

                // Calculate trend portion
                int256 absGradient = locals.newWeights[locals.i] >= 0
                    ? locals.newWeights[locals.i]
                    : -locals.newWeights[locals.i];

                int256 scaledAbsGradient = absGradient.div(locals.preExpScaling[locals.i].mul(TWO));
                trendPortion = _pow(scaledAbsGradient, locals.exponents[locals.i]);
            }
            // We want, in effect, a mean-reverting channel, so we want the channel portion to act as if it were
            // its own anti-momentum strategy (ie if there were no envelope, no trendPortion, we would want this
            // strategy to look like an anti-momentum strategy). Amplitude is required to be positive, so to achieve
            // this we can just negate the channel portion.
            channelPortion = -channelPortion;

            // The trendPortion variable so far has been calculated using the absolute value of the price gradient.
            // This is because x^y is not defined for negative x if y is not an integer. So we need to reintroduce
            // the sign of the price gradient to the trendPortion. We can use the sign of the price gradient to achieve this.
            if (locals.newWeights[locals.i] < 0) {
                trendPortion = -trendPortion;
            }


            trendPortion = trendPortion.mul(ONE - envelope);

            locals.signal[locals.i] = channelPortion + trendPortion;

            if (locals.kappa.length == 1) {
                locals.normalizationFactor += locals.signal[locals.i];
            } else {
                locals.normalizationFactor += locals.signal[locals.i].mul(locals.kappa[locals.i]);
            }

            unchecked {
                ++locals.i;
            }
        }

        newWeightsConverted = new int256[](locals.prevWeightLength);

        // Calculate final weights
        if (locals.kappa.length == 1) {
            locals.normalizationFactor /= int256(locals.prevWeightLength);
            for (locals.i = 0; locals.i < locals.prevWeightLength; ) {
                newWeightsConverted[locals.i] =
                    _prevWeights[locals.i] +
                    locals.kappa[0].mul(locals.signal[locals.i] - locals.normalizationFactor);

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
            for (locals.i = 0; locals.i < locals.prevWeightLength; ) {
                int256 weightUpdate = locals.kappa[locals.i].mul(locals.signal[locals.i] - locals.normalizationFactor);
                newWeightsConverted[locals.i] = _prevWeights[locals.i] + weightUpdate;
                require(newWeightsConverted[locals.i] >= 0, "Invalid weight");

                unchecked {
                    ++locals.i;
                }
            }
        }

        return newWeightsConverted;
    }

    /// @notice Check if the rule requires the previous moving average
    /// @return 0 if it does not require the previous moving average, 1 if it does
    function _requiresPrevMovingAverage() internal pure override returns (uint16) {
        return REQUIRES_PREV_MAVG;
    }

    /// @notice Set the initial intermediate values for the pool, in this case the gradient
    /// @param _poolAddress the target pool address
    /// @param _initialValues the initial values of the pool
    /// @param _numberOfAssets the number of assets in the pool
    function _setInitialIntermediateValues(
        address _poolAddress,
        int256[] memory _initialValues,
        uint _numberOfAssets
    ) internal override {
        _setGradient(_poolAddress, _initialValues, _numberOfAssets);
    }

    function validParameters(int256[][] calldata _parameters) external pure override returns (bool) {
        // Check parameters array length is 7
        if (_parameters.length != 7) return false;
        // All parameter arrays must have same length
        uint baseLength = _parameters[0].length;
        if (baseLength == 0) return false;

        for (uint i = 1; i < 6; i++) {
            if (_parameters[i].length != baseLength) {
                return false;
            }
        }

        // Validate parameter values
        for (uint i = 0; i < baseLength; i++) {
            if (_parameters[0][i] <= 0) return false; // kappa must be positive
            if (_parameters[1][i] <= 0) return false; // width must be positive
            if (_parameters[2][i] <= 0) return false; // amplitude must be positive
            if (_parameters[3][i] <= 0) return false; // exponents must be positive
            if (_parameters[4][i] <= 0) return false; // inverse scaling must be positive
            if (_parameters[5][i] <= 0) return false; // pre-exp scaling must be positive
        }
        // Check parameter 7 is scalar (length 1) and is either 0 or 1
        if (_parameters[6].length != 1) return false;
        if (_parameters[6][0] != 0 && _parameters[6][0] != PRBMathSD59x18.fromInt(1)) return false;

        return true;
    }
}
