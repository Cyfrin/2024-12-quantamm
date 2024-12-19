// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "../../UpdateWeightRunner.sol";
import "../../QuantAMMStorage.sol";
import "./QuantammBasedRuleHelpers.sol";

/// @title QuantAMMVarianceBasedRule contract for QuantAMM variance calculations and storage of variance for QuantAMM pools
/// @notice Contains the logic for calculating the variance of the pool price and storing the variance
contract QuantAMMVarianceBasedRule is ScalarRuleQuantAMMStorage {
    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    int256 private constant TENPOWEIGHTEEN = (10 ** 18);

    bool private immutable _protectedAccess;
    
    // Key is the pool address and stores the intermediate variance state in a packed array of 128 bit integers
    mapping(address => int256[]) internal intermediateVarianceStates;

    /// @dev struct to avoind stack to deep issues
    /// @notice Struct to store local variables for the variance calculation
    /// @param storageIndex index of the storage array
    /// @param secondIndex index of the second intermediate value
    /// @param intermediateState intermediate state during a variance calculation
    /// @param n number of assets in the pool
    /// @param nMinusOne n - 1
    /// @param notDivisibleByTwo boolean to check if n is not divisible by 2
    /// @param convertedLambda λ
    /// @param oneMinusLambda 1 - λ
    /// @param intermediateVarianceState intermediate state of the variance
    /// @param finalState final state of the variance
    struct QuantAMMVarianceLocals {
        uint256 storageIndex;
        uint256 secondIndex;
        int256 intermediateState;
        uint256 n;
        uint256 nMinusOne;
        bool notDivisibleByTwo;
        int256 convertedLambda;
        int256 oneMinusLambda;
        int256[] intermediateVarianceState;
        int256[] finalState;
    }

    /// @notice Calculates the new intermediate state for the variance update, i.e. the diagonal entries of A(t) = λA(t - 1) + (p(t) - p̅(t - 1))(p(t) - p̅(t))'
    /// @notice Calculates the new variances vector given the intermediate state, i.e. the diagonal entries of Σ(t) = (1 - λ)A(t)
    /// @param _newData p(t)
    /// @param _poolParameters _movingAverage p̅(t), _lambda λ, _numberOfAssets number of assets in the pool, _pool the target pool address
    function _calculateQuantAMMVariance(
        int256[] memory _newData,
        QuantAMMPoolParameters memory _poolParameters
    ) internal returns (int256[] memory) {
        QuantAMMVarianceLocals memory locals;
        locals.n = _poolParameters.numberOfAssets;
        locals.finalState = new int256[](locals.n);
        locals.intermediateVarianceState = _quantAMMUnpack128Array(
            intermediateVarianceStates[_poolParameters.pool],
            locals.n
        );
        locals.nMinusOne = locals.n - 1;
        locals.notDivisibleByTwo = locals.n % 2 != 0;
        locals.convertedLambda = int256(_poolParameters.lambda[0]);
        locals.oneMinusLambda = ONE - locals.convertedLambda;

        //the packed int256 slot index to store the intermediate variance state

        if (_poolParameters.lambda.length == 1) {
            //scalar parameters mean the calculation is simplified and even if it increases function and
            //contract size it decrease gas computed given iterative design tests
            if (locals.notDivisibleByTwo) {
                unchecked {
                    --locals.nMinusOne;
                }
            }

            for (uint i; i < locals.nMinusOne; ) {
                // Intermediate states are calculated in pairs to then SSTORE as we go along saving gas from a redundant SSTORE of length if we did the whole array
                // calculating and storing in the same loop also saves loop costs
                locals.intermediateState =
                    locals.convertedLambda.mul(locals.intermediateVarianceState[i]) +
                    (_newData[i] - _poolParameters.movingAverage[locals.n + i])
                        .mul(_newData[i] - _poolParameters.movingAverage[i])
                        .div(TENPOWEIGHTEEN); // p(t) - p̅(t - 1))_i * (p(t) - p̅(t))_i

                locals.intermediateVarianceState[i] = locals.intermediateState;
                locals.finalState[i] = locals.oneMinusLambda.mul(locals.intermediateState);

                unchecked {
                    locals.secondIndex = i + 1;
                }

                locals.intermediateState =
                    locals.convertedLambda.mul(locals.intermediateVarianceState[locals.secondIndex]) +
                    (_newData[locals.secondIndex] - _poolParameters.movingAverage[locals.n + locals.secondIndex])
                        .mul(_newData[locals.secondIndex] - _poolParameters.movingAverage[locals.secondIndex])
                        .div(TENPOWEIGHTEEN); // p(t) - p̅(t - 1))_i * (p(t) - p̅(t))_i

                locals.intermediateVarianceState[locals.secondIndex] = locals.intermediateState;
                intermediateVarianceStates[_poolParameters.pool][locals.storageIndex] = _quantAMMPackTwo128(
                    locals.intermediateVarianceState[i],
                    locals.intermediateVarianceState[locals.secondIndex]
                );

                locals.finalState[locals.secondIndex] = locals.oneMinusLambda.mul(locals.intermediateState);

                unchecked {
                    i += 2;
                    ++locals.storageIndex;
                }
            }

            if (locals.notDivisibleByTwo) {
                unchecked {
                    ++locals.nMinusOne;
                }
                locals.intermediateState =
                    locals.convertedLambda.mul(locals.intermediateVarianceState[locals.nMinusOne]) +
                    (_newData[locals.nMinusOne] - _poolParameters.movingAverage[locals.n + locals.nMinusOne])
                        .mul(_newData[locals.nMinusOne] - _poolParameters.movingAverage[locals.nMinusOne])
                        .div(TENPOWEIGHTEEN); // p(t) - p̅(t - 1))_i * (p(t) - p̅(t))_i

                locals.intermediateVarianceState[locals.nMinusOne] = locals.intermediateState;
                locals.finalState[locals.nMinusOne] = locals.oneMinusLambda.mul(locals.intermediateState);
                intermediateVarianceStates[_poolParameters.pool][locals.storageIndex] = locals
                    .intermediateVarianceState[locals.nMinusOne];
            }
        } else {
            //vector parameter calculation is the same but we have to keep track of and access the right vector parameter
            for (uint i; i < locals.nMinusOne; ) {
                unchecked {
                    locals.convertedLambda = int256(_poolParameters.lambda[i]);
                    locals.oneMinusLambda = ONE - locals.convertedLambda;
                }
                // p(t) - p̅(t - 1))_i * (p(t) - p̅(t))_i
                locals.intermediateState =
                    locals.convertedLambda.mul(locals.intermediateVarianceState[i]) +
                    (_newData[i] - _poolParameters.movingAverage[locals.n + i])
                        .mul(_newData[i] - _poolParameters.movingAverage[i])
                        .div(TENPOWEIGHTEEN);

                locals.intermediateVarianceState[i] = locals.intermediateState;
                locals.finalState[i] = locals.oneMinusLambda.mul(locals.intermediateState);

                unchecked {
                    locals.secondIndex = i + 1;
                    locals.convertedLambda = int256(_poolParameters.lambda[i + 1]);
                    locals.oneMinusLambda = ONE - locals.convertedLambda;
                }
                // p(t) - p̅(t - 1))_i * (p(t) - p̅(t))_i
                locals.intermediateState =
                    locals.convertedLambda.mul(locals.intermediateVarianceState[locals.secondIndex]) +
                    (_newData[locals.secondIndex] - _poolParameters.movingAverage[locals.n + locals.secondIndex])
                        .mul(_newData[locals.secondIndex] - _poolParameters.movingAverage[locals.secondIndex])
                        .div(TENPOWEIGHTEEN);

                locals.intermediateVarianceState[locals.secondIndex] = locals.intermediateState;

                intermediateVarianceStates[_poolParameters.pool][locals.storageIndex] = _quantAMMPackTwo128(
                    locals.intermediateVarianceState[i],
                    locals.intermediateVarianceState[locals.secondIndex]
                );
                locals.finalState[locals.secondIndex] = locals.oneMinusLambda.mul(locals.intermediateState);

                unchecked {
                    i += 2;
                    ++locals.storageIndex;
                }
            }

            if (locals.notDivisibleByTwo) {
                unchecked {
                    ++locals.nMinusOne;
                    locals.convertedLambda = int256(_poolParameters.lambda[locals.nMinusOne]);
                    locals.oneMinusLambda = ONE - locals.convertedLambda;
                }
                locals.intermediateState =
                    locals.convertedLambda.mul(locals.intermediateVarianceState[locals.nMinusOne]) +
                    (_newData[locals.nMinusOne] - _poolParameters.movingAverage[locals.n + locals.nMinusOne])
                        .mul(_newData[locals.nMinusOne] - _poolParameters.movingAverage[locals.nMinusOne])
                        .div(TENPOWEIGHTEEN); // p(t) - p̅(t - 1))_i * (p(t) - p̅(t))_i

                locals.intermediateVarianceState[locals.nMinusOne] = locals.intermediateState;
                locals.finalState[locals.nMinusOne] = locals.oneMinusLambda.mul(locals.intermediateState);
                intermediateVarianceStates[_poolParameters.pool][locals.storageIndex] = locals
                    .intermediateVarianceState[locals.nMinusOne];
            }
        }

        return locals.finalState;
    }

    /// @param _poolAddress the target pool address
    /// @param _initialValues the initial variance values
    /// @param _numberOfAssets the number of assets in the pool
    function _setIntermediateVariance(
        address _poolAddress,
        int256[] memory _initialValues,
        uint _numberOfAssets
    ) internal {
        uint storeLength = intermediateVarianceStates[_poolAddress].length;

        if ((storeLength == 0 && _initialValues.length == _numberOfAssets) || _initialValues.length == storeLength) {
            //should be during create pool
            intermediateVarianceStates[_poolAddress] = _quantAMMPack128Array(_initialValues);
        } else {
            revert("Invalid set variance");
        }
    }
}
