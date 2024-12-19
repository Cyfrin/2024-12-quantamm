// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./base/QuantammMathGuard.sol";
import "./base/QuantammMathMovingAverage.sol";
import "../UpdateWeightRunner.sol";
import "./base/QuantammBasedRuleHelpers.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IUpdateRule.sol";

/*
ARCHITECTURE DESIGN NOTES

TFMM specified oracle estimators are specified in base contracts inherited by update rule contracts.
A single deployment is required for multiple pools as intermediate state is keyed against the individual
pool address.

The update rule selection and its tuning is registered against a new pool when the pool is created. Use
of base contracts and benefits over library implementation is discussed in the technical appendix of the wp.

Initial versions created a math library with the oracle estimator functions and a separate library for the update rules, however external library calls and detached intermediate calculation value retrieval increased gas costs to an unsustainable level. 

An inherited base contract approach created a good domain driven design where both intermediate values and QuantAmm specific logic are stored in a single contract. 

*/
/// @title QuantAMMUpdateRule base contract for QuantAMM update rules
/// @notice Contains the logic for calculating the new weights of a QuantAMM pool and protections, must be implemented by all rules used in quantAMM
abstract contract UpdateRule is QuantAMMMathGuard, QuantAMMMathMovingAverage, IUpdateRule {
    uint16 private constant REQ_PREV_MAVG_VAL = 1;
    address private immutable updateWeightRunner;
    
    string public name;
    string[] public parameterDescriptions;

    /// @dev struct to avoid stack too deep issues
    /// @notice Struct to store local variables for the update rule
    /// @param i index for looping
    /// @param nMinusOne number of assets minus one
    /// @param numberOfAssets number of assets in the pool
    /// @param requiresPrevAverage boolean to determine if the rule requires the previous moving average
    /// @param intermediateMovingAverageStateLength length of the intermediate moving average state
    /// @param currMovingAverage current moving average
    /// @param updatedMovingAverage updated moving average
    /// @param calculationMovingAverage moving average used in the calculation
    /// @param intermediateGradientState intermediate gradient state
    /// @param unGuardedUpdatedWeights unguarded updated weights
    /// @param lambda lambda values
    /// @param secondIndex second index for looping
    /// @param storageIndex storage index for moving averages
    /// @param lastAssetIndex last asset index
    struct QuantAMMUpdateRuleLocals {
        uint i;
        uint nMinusOne;
        uint numberOfAssets;
        bool requiresPrevAverage;
        uint intermediateMovingAverageStateLength;
        int256[] currMovingAverage;
        int256[] updatedMovingAverage;
        int256[] calculationMovingAverage;
        int256[] intermediateGradientState;
        int256[] unGuardedUpdatedWeights;
        int128[] lambda;
        uint secondIndex;
        uint storageIndex;
        uint lastAssetIndex;
    }

    constructor(address _updateWeightRunner){
        updateWeightRunner = _updateWeightRunner;
    }

    /// @param _prevWeights the previous weights retrieved from the vault
    /// @param _data the latest data from the signal, usually price
    /// @param _pool the target pool address
    /// @param _parameters the parameters of the rule that are not lambda
    /// @param _lambdaStore either vector or scalar lambda
    /// @param _epsilonMax the maximum weights can change in a given update interval
    /// @param _absoluteWeightGuardRail the maximum weight a token can have
    function CalculateNewWeights(
        int256[] calldata _prevWeights,
        int256[] calldata _data,
        address _pool,
        int256[][] calldata _parameters,
        uint64[] calldata _lambdaStore,
        uint64 _epsilonMax,
        uint64 _absoluteWeightGuardRail
    ) external returns (int256[] memory updatedWeights) {
        require(msg.sender == updateWeightRunner, "UNAUTH_CALC");

        QuantAMMUpdateRuleLocals memory locals;

        locals.numberOfAssets = _prevWeights.length;
        locals.nMinusOne = locals.numberOfAssets - 1;
        locals.lambda = new int128[](_lambdaStore.length);

        for (locals.i; locals.i < locals.lambda.length; ) {
            locals.lambda[locals.i] = int128(uint128(_lambdaStore[locals.i]));
            unchecked {
                ++locals.i;
            }
        }

        locals.requiresPrevAverage = _requiresPrevMovingAverage() == REQ_PREV_MAVG_VAL;
        locals.intermediateMovingAverageStateLength = locals.numberOfAssets;

        if (locals.requiresPrevAverage) {
            unchecked {
                locals.intermediateMovingAverageStateLength *= 2;
            }
        }

        locals.currMovingAverage = new int256[](locals.numberOfAssets);
        locals.updatedMovingAverage = new int256[](locals.numberOfAssets);
        locals.calculationMovingAverage = new int256[](locals.intermediateMovingAverageStateLength);

        locals.currMovingAverage = _quantAMMUnpack128Array(movingAverages[_pool], locals.numberOfAssets);

        //All rules require the use of moving averages so the logic is executed in the base
        locals.updatedMovingAverage = _calculateQuantAMMMovingAverage(
            locals.currMovingAverage,
            _data,
            locals.lambda,
            locals.numberOfAssets
        );

        if (locals.numberOfAssets % 2 != 0) {
            unchecked {
                --locals.nMinusOne;
            }
        }

        locals.secondIndex;
        locals.storageIndex;

        // The packing and storing of moving averages is done per slot to save on SSTORES
        // The potential sticky end if there is an odd number if constituents is dealt at the end
        // The saving of one SSTORE is more than the extra logic gas
        locals.i = 0;
        for (; locals.i < locals.nMinusOne; ) {
            if (locals.requiresPrevAverage) {
                locals.calculationMovingAverage[locals.i + locals.numberOfAssets] = locals.currMovingAverage[locals.i];
            }
            locals.calculationMovingAverage[locals.i] = locals.updatedMovingAverage[locals.i];

            unchecked {
                locals.secondIndex = locals.i + 1;
            }
            if (locals.requiresPrevAverage) {
                locals.calculationMovingAverage[locals.secondIndex + locals.numberOfAssets] = locals.currMovingAverage[
                    locals.secondIndex
                ];
            }
            locals.calculationMovingAverage[locals.secondIndex] = locals.updatedMovingAverage[locals.secondIndex];

            if (!locals.requiresPrevAverage) {
                movingAverages[_pool][locals.storageIndex] = _quantAMMPackTwo128(
                    locals.updatedMovingAverage[locals.i],
                    locals.updatedMovingAverage[locals.secondIndex]
                );
            }

            unchecked {
                ++locals.storageIndex;
                locals.i += 2;
            }
        }

        if (locals.numberOfAssets % 2 != 0) {
            locals.lastAssetIndex = locals.numberOfAssets - 1;
            unchecked {
                locals.nMinusOne = ((locals.lastAssetIndex) / 2);
            }
            if (locals.requiresPrevAverage) {
                locals.calculationMovingAverage[locals.lastAssetIndex + locals.numberOfAssets] = locals
                    .currMovingAverage[locals.lastAssetIndex];
            }
            locals.calculationMovingAverage[locals.lastAssetIndex] = locals.updatedMovingAverage[locals.lastAssetIndex];
            if (!locals.requiresPrevAverage) {
                movingAverages[_pool][locals.nMinusOne] = locals.updatedMovingAverage[locals.lastAssetIndex];
            }
        }

        //because of mixing of prev and current if the numassets is odd it is makes normal code unreadable to do inline
        //this means for rules requiring prev moving average there is an addition SSTORE and local packed array
        if (locals.requiresPrevAverage) {
            movingAverages[_pool] = _quantAMMPack128Array(locals.calculationMovingAverage);
        }

        QuantAMMPoolParameters memory poolParameters;
        poolParameters.lambda = locals.lambda;
        poolParameters.movingAverage = locals.calculationMovingAverage;
        poolParameters.pool = _pool;

        //calling the function in the derived contract specific to the specific rule
        locals.unGuardedUpdatedWeights = _getWeights(_prevWeights, _data, _parameters, poolParameters);

        //Guard weights is done in the base contract so regardless of the rule the logic will always be executed
        updatedWeights = _guardQuantAMMWeights(
            locals.unGuardedUpdatedWeights,
            _prevWeights,
            int128(uint128(_epsilonMax)),
            int128(uint128(_absoluteWeightGuardRail))
        );
    }

    /// @notice Function that has to be implemented by update rules. Given previous weights, current data, and current gradient of the data, calculate the new weights.
    /// @param _prevWeights w(t - 1), the weights at the previous timestamp
    /// @param _data p(t), the data at the current timestamp, usually referring to prices (but could also be other values that are returned by an oracle)
    /// @param _parameters Arbitrary values that parametrize the rule, interpretation depends on rule
    /// @param _poolParameters PoolParameters
    /// @return newWeights w(t), the updated weights
    function _getWeights(
        int256[] calldata _prevWeights,
        int256[]  memory _data,
        int256[][] calldata _parameters,
        QuantAMMPoolParameters memory _poolParameters
    ) internal virtual returns (int256[] memory newWeights);

    function _requiresPrevMovingAverage() internal pure virtual returns (uint16);

    /// @param _poolAddress address of pool being initialised
    /// @param _initialValues the initial intermediate values to be saved
    /// @param _numberOfAssets the number of assets in the pool
    function _setInitialIntermediateValues(
        address _poolAddress,
        int256[] memory _initialValues,
        uint _numberOfAssets
    ) internal virtual;

    /// @param _poolAddress address of pool being initialised
    /// @param _newMovingAverages the initial moving averages to be saved
    /// @param _newInitialValues the initial intermediate values to be saved
    /// @param _numberOfAssets the number of assets in the pool
    /// @notice top level initialisation function to be called during pool registration
    function initialisePoolRuleIntermediateValues(
        address _poolAddress,
        int256[] memory _newMovingAverages,
        int256[] memory _newInitialValues,
        uint _numberOfAssets
    ) external {
        //initialisation is controlled during the registration process
        //this is to make sure no external actor can call this function
        require(msg.sender == _poolAddress || msg.sender == updateWeightRunner, "UNAUTH");
        _setInitialMovingAverages(_poolAddress, _newMovingAverages, _numberOfAssets);
        _setInitialIntermediateValues(_poolAddress, _newInitialValues, _numberOfAssets);
    }

    /// @notice Check if the given parameters are valid for the rule
    function validParameters(int256[][] calldata parameters) external view virtual returns (bool);
}
