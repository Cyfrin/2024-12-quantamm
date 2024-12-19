// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";

/// @title QuantAMMMathGuard contract to implement guard rails for QuantAMM weights updates
/// @notice This contract implements the guard rails for QuantAMM weights updates as described in the QuantAMM whitepaper.
abstract contract QuantAMMMathGuard {
    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    int256 private constant TWO = 2 * 1e18;

    /// @notice Guards QuantAMM weights updates
    /// @param _weights Raw weights to be guarded and normalized
    /// @param _prevWeights Previous weights to be used for normalization
    /// @param _epsilonMax  Maximum allowed change in weights per update step (epsilon) in the QuantAMM whitepaper
    /// @param _absoluteWeightGuardRail Maximum allowed weight in the QuantAMM whitepaper
    function _guardQuantAMMWeights(
        int256[] memory _weights,
        int256[] calldata _prevWeights,
        int256 _epsilonMax,
        int256 _absoluteWeightGuardRail
    ) internal pure returns (int256[] memory guardedNewWeights) {
        // first see if the weights go beyond the maximum/minimum weights
        _weights = _clampWeights(_weights, _absoluteWeightGuardRail);

        //then reduce even further if the weight change is beyond the allowed "speed limit" that protects the changes from front running
        guardedNewWeights = _normalizeWeightUpdates(_prevWeights, _weights, _epsilonMax);
    }

    /// @dev there are some edge cases where the clamping might result to break the guard rail. This is known and the last interpolation block logic in the update weight runner is an ultimate guard against this.
    /// @notice Applies guard rails (min value, max value) to weights and returns the normalized weights
    /// @param _weights Raw weights
    /// @return Clamped weights
    function _clampWeights(
        int256[] memory _weights,
        int256 _absoluteWeightGuardRail
    ) internal pure returns (int256[] memory) {
        unchecked {
            uint weightLength = _weights.length;
            if (weightLength == 1) {
                return _weights;
            }
            int256 absoluteMin = _absoluteWeightGuardRail;
            int256 absoluteMax = ONE -
                (PRBMathSD59x18.fromInt(int256(_weights.length - 1)).mul(_absoluteWeightGuardRail));
            int256 sumRemainerWeight = ONE;
            int256 sumOtherWeights;

            for (uint i; i < weightLength; ++i) {
                if (_weights[i] < absoluteMin) {
                    _weights[i] = absoluteMin;
                    sumRemainerWeight -= absoluteMin;
                } else if (_weights[i] > absoluteMax) {
                    _weights[i] = absoluteMax;
                    sumOtherWeights += absoluteMax;
                }
            }
            if (sumOtherWeights != 0) {
                int256 proportionalRemainder = sumRemainerWeight.div(sumOtherWeights);
                for (uint i; i < weightLength; ++i) {
                    if (_weights[i] != absoluteMin) {
                        _weights[i] = _weights[i].mul(proportionalRemainder);
                    }
                }
            }
        }
        return _weights;
    }

    ///@notice Normalizes the weights to ensure that the sum of the weights is equal to 1
    ///@param _prevWeights Previous weights
    ///@param _newWeights New weights
    ///@param _epsilonMax Maximum allowed change in weights per update step (epsilon) in the QuantAMM whitepaper
    function _normalizeWeightUpdates(
        int256[] memory _prevWeights,
        int256[] memory _newWeights,
        int256 _epsilonMax
    ) internal pure returns (int256[] memory) {
        unchecked {
            int256 maxAbsChange = _epsilonMax;
            for (uint i; i < _prevWeights.length; ++i) {
                int256 absChange;
                if (_prevWeights[i] > _newWeights[i]) {
                    absChange = _prevWeights[i] - _newWeights[i];
                } else {
                    absChange = _newWeights[i] - _prevWeights[i];
                }
                if (absChange > maxAbsChange) {
                    maxAbsChange = absChange;
                }
            }
            int256 newWeightsSum;
            if (maxAbsChange > _epsilonMax) {
                int256 rescaleFactor = _epsilonMax.div(maxAbsChange);
                for (uint i; i < _newWeights.length; ++i) {
                    int256 newDelta = (_newWeights[i] - _prevWeights[i]).mul(rescaleFactor);
                    _newWeights[i] = _prevWeights[i] + newDelta;
                    newWeightsSum += _newWeights[i];
                }
            } else {
                for (uint i; i < _newWeights.length; ++i) {
                    newWeightsSum += _newWeights[i];
                }
            }
            // There might a very small (1e-18) rounding error, add this to the first element.
            // In some edge cases, this might break a guard rail, but only by 1e-18, which is modelled to be acceptable.
            _newWeights[0] = _newWeights[0] + (ONE - newWeightsSum);
        }
        return _newWeights;
    }

    /// @notice Raises SD59x18 number x to an arbitrary SD59x18 number y
    /// @dev Calculates (2^(log2(x)))^y == x^y == 2^(log2(x) * y)
    /// @param _x Base
    /// @param _y Exponent
    /// @return result x^y
    function _pow(int256 _x, int256 _y) internal pure returns (int256 result) {
        if (_y == 0 || (_x == 0 && _y == 0)) {
            return 1 * 1e18;
        }
        if (_x == 0) {
            return 0;
        }

        //Noticed effect of this reorg- 2^(log2(x) * y) - the variable multiplied by exp2() can be a large negative and lib can return 0
        return _y.mul(_x.log2()).exp2();
    }
}
