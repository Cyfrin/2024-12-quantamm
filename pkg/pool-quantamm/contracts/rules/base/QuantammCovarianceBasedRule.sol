// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "../../UpdateWeightRunner.sol";
import "../../QuantAMMStorage.sol";
import "./QuantammBasedRuleHelpers.sol";

/// @title QuantAMMCovarianceBasedRule contract base for QuantAMM rules that use covariance matrices to calculate the new weights of a pool
/// @notice This contract is abstract and needs to be inherited and implemented to be used. It also stores the intermediate values of all pools
abstract contract QuantAMMCovarianceBasedRule is VectorRuleQuantAMMStorage {
    using PRBMathSD59x18 for int256;

    int256 private constant ONE = 1 * 1e18; // Result of PRBMathSD59x18.fromInt(1), store as constant to avoid recalculation every time
    int256 private constant TENPOWEIGHTEEN = (10 ** 18);

    //key is pool address, value is the intermediate state of the covariance matrix in a packed array of 128 bit integers
    mapping(address => int256[]) internal intermediateCovarianceStates;

    /// @dev struct to avoind stack to deep issues
    /// @notice Struct to store local variables for the covariance calculation
    /// @param n Dimension of square matrix
    /// @param nSquared n * n
    /// @param intermediateCovarianceState intermediate state of the covariance matrix
    /// @param newState new state of the covariance matrix
    /// @param u (p(t) - p̅(t - 1))
    /// @param v (p(t) - p̅(t))
    /// @param convertedLambda λ
    /// @param oneMinusLambda 1 - λ
    /// @param intermediateState intermediate state during a covariance matrix calculation
    struct QuantAMMCovariance {
        uint256 n;
        uint256 nSquared;
        int256[][] intermediateCovarianceState;
        int256[][] newState;
        int256[] u;
        int256[] v;
        int256 convertedLambda;
        int256 oneMinusLambda;
        int256 intermediateState;
    }

    /// @notice Calculates the new intermediate state for the covariance update, i.e. A(t) = λA(t - 1) + (p(t) - p̅(t - 1))(p(t) - p̅(t))'
    /// @param _newData p(t)
    /// @param _poolParameters pool parameters
    /// @return newState new state of the covariance matrix
    function _calculateQuantAMMCovariance(
        int256[]  memory _newData,
        QuantAMMPoolParameters memory _poolParameters
    ) internal returns (int256[][] memory) {
        QuantAMMCovariance memory locals;
        locals.n = _poolParameters.numberOfAssets; // Dimension of square matrix
        locals.nSquared = locals.n * locals.n;
        int256[][] memory intermediateCovarianceState = _quantAMMUnpack128Matrix(
            intermediateCovarianceStates[_poolParameters.pool],
            locals.n
        );

        int256[][] memory newState = new int256[][](locals.nSquared);

        locals.u = new int256[](locals.n); // (p(t) - p̅(t - 1))
        locals.v = new int256[](locals.n); // (p(t) - p̅(t))

        for (uint i; i < locals.n; ) {
            locals.u[i] = _newData[i] - _poolParameters.movingAverage[i + locals.n];
            locals.v[i] = _newData[i] - _poolParameters.movingAverage[i];
            unchecked {
                ++i;
            }
        }

        //parameters are either scalar or vector defined. This if statement increases function and contract footprint
        // however it says considerable compute cost if scalar parameters are defined.
        if (_poolParameters.lambda.length == 1) {
            unchecked {
                locals.convertedLambda = int256(_poolParameters.lambda[0]);
                locals.oneMinusLambda = ONE - locals.convertedLambda;
            }
            for (uint i; i < locals.n; ) {
                newState[i] = new int256[](locals.n);
                for (uint j; j < locals.n; ) {
                    //Better to do this item by item saving 2 SSTORES by not changing the length
                    // locals.u and locals.v are in 18 decimals, need to scale back the result to 18 decimals
                    locals.intermediateState =
                        locals.convertedLambda.mul(intermediateCovarianceState[i][j]) +
                        locals.u[i].mul(locals.v[j]).div(TENPOWEIGHTEEN); // i is the row, j the column -> u_i * v_j the result of the outer product.

                    newState[i][j] = locals.intermediateState.mul(locals.oneMinusLambda);
                    intermediateCovarianceState[i][j] = locals.intermediateState;
                    unchecked {
                        ++j;
                    }
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            //vector calculation the same apart from accessing the lambda array for each element
            for (uint i; i < locals.n; ) {
                unchecked {
                    locals.convertedLambda = int256(_poolParameters.lambda[i]);
                    locals.oneMinusLambda = ONE - locals.convertedLambda;
                }
                newState[i] = new int256[](locals.n);
                for (uint j; j < locals.n; ) {
                    //Better to do this item by item saving 2 SSTORES by not changing the length
                    // locals.u and locals.v are in 18 decimals, need to scale back the result to 18 decimals
                    locals.intermediateState =
                        locals.convertedLambda.mul(intermediateCovarianceState[i][j]) +
                        locals.u[i].mul(locals.v[j]).div(TENPOWEIGHTEEN); // i is the row, j the column -> u_i * v_j the result of the outer product.
                    newState[i][j] = locals.intermediateState.mul(locals.oneMinusLambda);
                    intermediateCovarianceState[i][j] = locals.intermediateState;
                    unchecked {
                        ++j;
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        _quantAMMPack128Matrix(intermediateCovarianceState, intermediateCovarianceStates[_poolParameters.pool]);

        return newState;
    }

    /// @param _poolAddress the pool address being initialised
    /// @param _initialValues the values passed in during the creation of the pool
    /// @param _numberOfAssets  the number of assets in the pool being initialised
    function _setIntermediateCovariance(
        address _poolAddress,
        int256[][] memory _initialValues,
        uint _numberOfAssets
    ) internal {
        uint storeLength = intermediateCovarianceStates[_poolAddress].length;
        if ((storeLength == 0 && _initialValues.length == _numberOfAssets) || _initialValues.length == storeLength) {
            for (uint i; i < _numberOfAssets; ) {
                require(_initialValues[i].length == _numberOfAssets, "Bad init covar row");
                unchecked {
                    ++i;
                }
            }
            if (storeLength == 0) {
                if ((_numberOfAssets * _numberOfAssets) % 2 == 0) {
                    intermediateCovarianceStates[_poolAddress] = new int256[]((_numberOfAssets * _numberOfAssets) / 2);
                } else {
                    intermediateCovarianceStates[_poolAddress] = new int256[](
                        (((_numberOfAssets * _numberOfAssets) - 1) / 2) + 1
                    );
                }
            }

            //should be initiiduring create pool
            _quantAMMPack128Matrix(_initialValues, intermediateCovarianceStates[_poolAddress]);
        } else {
            revert("Invalid set covariance");
        }
    }
}
