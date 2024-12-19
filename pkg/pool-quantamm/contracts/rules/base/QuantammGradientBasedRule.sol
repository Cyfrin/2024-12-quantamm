// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "../../UpdateWeightRunner.sol";
import "./QuantammBasedRuleHelpers.sol";
import "../../QuantAMMStorage.sol";

/// @title QuantAMMGradientBasedRule contract calculates gradients for QuantAMM rules that use covariance matrices to calculate the new weights of a pool
/// @notice This contract is abstract and needs to be inherited and implemented to be used.
abstract contract QuantAMMGradientBasedRule is ScalarRuleQuantAMMStorage {
    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    int256 private constant THREE = 3 * 1e18;

    // key is pool address, value is the intermediate state of the gradient in a packed array of 128 bit integers
    mapping(address => int256[]) internal intermediateGradientStates;

    /// @dev struct to avoind stack to deep issues
    /// @notice Struct to store local variables for the gradient calculation
    /// @param mulFactor λ^3 / (1 - λ)
    /// @param intermediateValue intermediate value during a gradient calculation
    /// @param secondIntermediateValue second intermediate value during a gradient calculation
    /// @param secondIndex index of the second intermediate value
    /// @param storageArrayIndex index of the storage array
    /// @param finalValues final values of the gradient
    /// @param intermediateGradientState intermediate state during a gradient calculation
    struct QuantAMMGradientLocals {
        int256 mulFactor;
        int256 intermediateValue;
        int256 secondIntermediateValue;
        uint256 secondIndex;
        uint256 storageArrayIndex;
        int256[] finalValues;
        int256[] intermediateGradientState;
    }

    /// @param _newData p(t)
    /// @param _poolParameters pool parameters
    function _calculateQuantAMMGradient(
        int256[]  memory _newData,
        QuantAMMPoolParameters memory _poolParameters
    ) internal returns (int256[] memory) {
        QuantAMMGradientLocals memory locals;
        locals.finalValues = new int256[](_poolParameters.numberOfAssets);
        locals.intermediateGradientState = _quantAMMUnpack128Array(
            intermediateGradientStates[_poolParameters.pool],
            _poolParameters.numberOfAssets
        );

        // lots initialised before looping to save gas
        bool notDivisibleByTwo = _poolParameters.numberOfAssets % 2 != 0;
        uint numberOfAssetsMinusOne = _poolParameters.numberOfAssets - 1;
        int256 convertedLambda = int256(_poolParameters.lambda[0]);
        int256 oneMinusLambda = ONE - convertedLambda;

        //You cannot have a one token pool so if its one element you know it's scalar
        if (_poolParameters.lambda.length == 1) {
            unchecked {
                locals.mulFactor = oneMinusLambda.pow(THREE).div(convertedLambda);

                if (notDivisibleByTwo) {
                    --numberOfAssetsMinusOne;
                }
            }

            //the reason for this loop complexity is to save gas as the packing and SSTORE can be done
            //individually saving on the SSTORE from the length update if you were to replace the array
            // condition is number of assets minus one because we are doing two at a time and the last one is done outside the loop
            for (uint i; i < numberOfAssetsMinusOne; ) {
                // a(t) = λa(t - 1) + (p(t) - p̅(t)) / (1 - λ)
                locals.intermediateValue =
                    convertedLambda.mul(locals.intermediateGradientState[i]) +
                    (_newData[i] - _poolParameters.movingAverage[i]).div(oneMinusLambda);

                locals.intermediateGradientState[i] = locals.intermediateValue;
                locals.finalValues[i] = locals.mulFactor.mul(locals.intermediateValue);

                unchecked {
                    locals.secondIndex = i + 1;
                }

                locals.secondIntermediateValue =
                    convertedLambda.mul(locals.intermediateGradientState[locals.secondIndex]) +
                    (_newData[locals.secondIndex] - _poolParameters.movingAverage[locals.secondIndex]).div(
                        oneMinusLambda
                    );

                locals.finalValues[locals.secondIndex] = locals.mulFactor.mul(locals.secondIntermediateValue);

                intermediateGradientStates[_poolParameters.pool][locals.storageArrayIndex] = _quantAMMPackTwo128(
                    locals.intermediateGradientState[i],
                    locals.secondIntermediateValue
                );
                // the storage array is tracked separately
                unchecked {
                    i += 2;
                    ++locals.storageArrayIndex;
                }
            }

            //now have to handle final sticky end if not divisible by two
            if (notDivisibleByTwo) {
                unchecked {
                    ++numberOfAssetsMinusOne;
                }

                locals.intermediateValue =
                    convertedLambda.mul(locals.intermediateGradientState[numberOfAssetsMinusOne]) +
                    (_newData[numberOfAssetsMinusOne] - _poolParameters.movingAverage[numberOfAssetsMinusOne]).div(
                        oneMinusLambda
                    );

                intermediateGradientStates[_poolParameters.pool][locals.storageArrayIndex] = locals.intermediateValue;

                locals.finalValues[numberOfAssetsMinusOne] = locals.mulFactor.mul(locals.intermediateValue);
            }
        } else {
            // if the parameters are defined as per constituent we do the same as the if loop but
            //tracking the appropriate lambda for each asset and the appropriate storage index
            if (notDivisibleByTwo) {
                --numberOfAssetsMinusOne;
            }

            for (uint i; i < numberOfAssetsMinusOne; ) {
                unchecked {
                    convertedLambda = int256(_poolParameters.lambda[i]);
                    oneMinusLambda = ONE - convertedLambda;
                    locals.mulFactor = oneMinusLambda.pow(THREE).div(convertedLambda);
                }

                // a(t) = λa(t - 1) + (p(t) - p̅(t)) / (1 - λ)
                locals.intermediateValue =
                    convertedLambda.mul(locals.intermediateGradientState[i]) +
                    (_newData[i] - _poolParameters.movingAverage[i]).div(oneMinusLambda);

                locals.intermediateGradientState[i] = locals.intermediateValue;
                locals.finalValues[i] = locals.mulFactor.mul(locals.intermediateValue);

                unchecked {
                    locals.secondIndex = i + 1;
                    convertedLambda = int256(_poolParameters.lambda[locals.secondIndex]);
                    oneMinusLambda = ONE - convertedLambda;
                    locals.mulFactor = oneMinusLambda.pow(THREE).div(convertedLambda);
                }

                locals.secondIntermediateValue =
                    convertedLambda.mul(locals.intermediateGradientState[locals.secondIndex]) +
                    (_newData[locals.secondIndex] - _poolParameters.movingAverage[locals.secondIndex]).div(
                        oneMinusLambda
                    );

                locals.finalValues[locals.secondIndex] = locals.mulFactor.mul(locals.secondIntermediateValue);

                intermediateGradientStates[_poolParameters.pool][i] = _quantAMMPackTwo128(
                    locals.intermediateGradientState[i],
                    locals.secondIntermediateValue
                );
                unchecked {
                    i += 2;
                    ++locals.storageArrayIndex;
                }
            }

            //take care of the potential sticky end if not divisible by two
            if (notDivisibleByTwo) {
                unchecked {
                    ++numberOfAssetsMinusOne;
                    convertedLambda = int256(_poolParameters.lambda[numberOfAssetsMinusOne]);
                    oneMinusLambda = ONE - convertedLambda;
                    locals.mulFactor = oneMinusLambda.pow(THREE).div(convertedLambda);
                }

                locals.intermediateValue =
                    convertedLambda.mul(locals.intermediateGradientState[numberOfAssetsMinusOne]) +
                    (_newData[numberOfAssetsMinusOne] - _poolParameters.movingAverage[numberOfAssetsMinusOne]).div(
                        oneMinusLambda
                    );

                locals.finalValues[numberOfAssetsMinusOne] = locals.mulFactor.mul(locals.intermediateValue);

                intermediateGradientStates[_poolParameters.pool][locals.storageArrayIndex] = locals.intermediateValue;
            }
        }

        return locals.finalValues;
    }

    /// @param poolAddress the pool address being initialised
    /// @param _initialValues the values passed in during the creation of the pool
    /// @param _numberOfAssets the number of assets in the pool being initialised
    function _setGradient(address poolAddress, int256[] memory _initialValues, uint _numberOfAssets) internal {
        uint storeLength = intermediateGradientStates[poolAddress].length;
        if ((storeLength == 0 && _initialValues.length == _numberOfAssets) || _initialValues.length == storeLength) {
            //should be during create pool
            intermediateGradientStates[poolAddress] = _quantAMMPack128Array(_initialValues);
        } else {
            revert("Invalid set gradient");
        }
    }
}
