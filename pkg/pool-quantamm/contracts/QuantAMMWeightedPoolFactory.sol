// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { IQuantAMMWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";
import { QuantAMMWeightedPool } from "./QuantAMMWeightedPool.sol";

/**
 * @param name The name of the pool
* @param symbol The symbol of the pool
* @param tokens An array of descriptors for the tokens the pool will manage
* @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
* @param roleAccounts Addresses the Vault will allow to change certain pool settings
* @param swapFeePercentage Initial swap fee percentage
* @param poolHooksContract Contract that implements the hooks for the pool
* @param enableDonation If true, the pool will support the donation add liquidity mechanism
* @param disableUnbalancedLiquidity If true, only proportional add and remove liquidity are accepted
* @param salt The salt value that will be passed to create3 deployment

 */

/**
 * @notice General Weighted Pool factory
 * @dev This is the most general factory, which allows up to eight tokens and arbitrary weights.
 */
contract QuantAMMWeightedPoolFactory is IPoolVersion, BasePoolFactory, Version {
    // solhint-disable not-rely-on-time

    struct NewPoolParams {
        string name;
        string symbol;
        TokenConfig[] tokens;
        uint256[] normalizedWeights;
        PoolRoleAccounts roleAccounts;
        uint256 swapFeePercentage;
        address poolHooksContract;
        bool enableDonation;
        bool disableUnbalancedLiquidity;
        bytes32 salt;
        int256[] _initialWeights;
        IQuantAMMWeightedPool.PoolSettings _poolSettings;
        int256[] _initialMovingAverages;
        int256[] _initialIntermediateValues;
        uint256 _oracleStalenessThreshold;
        uint256 poolRegistry;
        string[][] poolDetails;
    }

    string private _poolVersion;
    address private immutable _updateWeightRunner;

    /// @param vault the balancer v3 valt
    /// @param pauseWindowDuration the pause duration
    /// @param factoryVersion factory version
    /// @param poolVersion pool version
    /// @param updateWeightRunner singleton update weight runner
    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address updateWeightRunner
    ) BasePoolFactory(vault, pauseWindowDuration, type(QuantAMMWeightedPool).creationCode) Version(factoryVersion) {
        require(updateWeightRunner != address(0), "update weight runner cannot be default address");
        _poolVersion = poolVersion;
        _updateWeightRunner = updateWeightRunner;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    function createWithoutArgs(NewPoolParams memory params) external returns (address pool) {
        if (params.roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.enableDonation = params.enableDonation;
        // disableUnbalancedLiquidity must be set to true if a hook has the flag enableHookAdjustedAmounts = true.
        liquidityManagement.disableUnbalancedLiquidity = params.disableUnbalancedLiquidity;
        
        pool = _create(abi.encode(
                QuantAMMWeightedPool.NewPoolParams({
                    name: params.name,
                    symbol: params.symbol,
                    numTokens: params.normalizedWeights.length,
                    version: "version",
                    updateWeightRunner: _updateWeightRunner,
                    poolRegistry: params.poolRegistry,
                    poolDetails: params.poolDetails
                }),
                getVault()
            ), params.salt);

        QuantAMMWeightedPool(pool).initialize(
            params._initialWeights,
            params._poolSettings,
            params._initialMovingAverages,
            params._initialIntermediateValues,
            params._oracleStalenessThreshold
        );

        _registerPoolWithVault(
            pool,
            params.tokens,
            params.swapFeePercentage,
            false, // not exempt from protocol fees
            params.roleAccounts,
            params.poolHooksContract,
            liquidityManagement
        );
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @dev Tokens must be sorted for pool registration.
     */
    function create(NewPoolParams memory params) external returns (address pool, bytes memory poolArgs) {
        if (params.roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.enableDonation = params.enableDonation;
        // disableUnbalancedLiquidity must be set to true if a hook has the flag enableHookAdjustedAmounts = true.
        liquidityManagement.disableUnbalancedLiquidity = params.disableUnbalancedLiquidity;
        poolArgs = abi.encode(
                QuantAMMWeightedPool.NewPoolParams({
                    name: params.name,
                    symbol: params.symbol,
                    numTokens: params.normalizedWeights.length,
                    version: "version",
                    updateWeightRunner: _updateWeightRunner,
                    poolRegistry: params.poolRegistry,
                    poolDetails: params.poolDetails
                }),
                getVault()
            );

        pool = _create(poolArgs, params.salt);

        QuantAMMWeightedPool(pool).initialize(
            params._initialWeights,
            params._poolSettings,
            params._initialMovingAverages,
            params._initialIntermediateValues,
            params._oracleStalenessThreshold
        );

        _registerPoolWithVault(
            pool,
            params.tokens,
            params.swapFeePercentage,
            false, // not exempt from protocol fees
            params.roleAccounts,
            params.poolHooksContract,
            liquidityManagement
        );
    }
}
