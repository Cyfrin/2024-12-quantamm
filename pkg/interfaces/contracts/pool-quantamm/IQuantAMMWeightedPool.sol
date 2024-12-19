// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./IUpdateRule.sol";

/// @title the main central quantammBase containing records and balances of all pools. Contains all user-pool interaction functions.
interface IQuantAMMWeightedPool {
    /**
     * @notice Snapshot of current Weighted Pool data that can change.
     * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
     * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
     * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
     *
     * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     * @param tokenRates 18-decimal FP values for rate tokens (e.g., yield-bearing), or FP(1) for standard tokens
     * @param totalSupply The current total supply of the pool tokens (BPT)
     * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
     * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
     * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
     * @param weightsAtLastUpdateInterval The weights of the pool at the last update interval
     * @param weightBlockMultipliers The block multipliers for the weights
     * @param lastUpdateIntervalTime The last time the pool was updated
     * @param lastInterpolationTimePossible The last time that the weights can be updated given the block multiplier before one weight hits the guardrail
     */
    struct QuantAMMWeightedPoolDynamicData {
        uint256[] balancesLiveScaled18;
        uint256[] tokenRates;
        uint256 totalSupply;
        bool isPoolInitialized;
        bool isPoolPaused;
        bool isPoolInRecoveryMode;
        int256[] weightsAtLastUpdateInterval;
        int256[] weightBlockMultipliers;
        uint40 lastUpdateIntervalTime;
        uint40 lastInterpolationTimePossible;
    }
    
    /**
     * @notice Weighted Pool data that cannot change after deployment.
        * @param tokens Pool tokens, sorted in pool registration order
        * @param oracleStalenessThreshold The acceptable number of blocks behind the current that an oracle value can be
        * @param poolRegistry The address of the pool registry
        * @param ruleParameters The parameters for the rule, validated in each rule separately during set rule
        * @param lambda Decay parameter for exponentially-weighted moving average (0 < λ < 1)
        * @param epsilonMax Maximum allowed delta for a weight update, stored as SD59x18 number
        * @param absoluteWeightGuardRail Maximum allowed absolute weight allowed.
        * @param maxTradeSizeRatio maximum trade size allowed as a fraction of the pool
        * @param updateInterval Minimum amount of seconds between two updates
     */
    struct QuantAMMWeightedPoolImmutableData {
        IERC20[] tokens;
        uint oracleStalenessThreshold;
        uint256 poolRegistry;
        int256[][] ruleParameters;
        uint64[] lambda;
        uint64 epsilonMax;
        uint64 absoluteWeightGuardRail;
        uint256 maxTradeSizeRatio;
        uint64 updateInterval;
    }

    ///@notice the time variables used for interpolation
    ///@param lastUpdateIntervalTime the last time the pool was updated, this is the time of the weights prior to multiplier being added to it.abi
    ///@param lastPossibleInterpolationTime the last time that the weights can be updated given the block multiplier before one weight hits the guardrail
    struct QuantAMMBaseInterpolationVariables {
        uint40 lastUpdateIntervalTime;
        uint40 lastPossibleInterpolationTime;
    }

    ///@notice the data needed to get the weights of the pool
    ///@param quantAMMBaseInterpolationDetails the time variables used for interpolation
    ///@param assets the assets of the pool

    ///@notice the data needed to get the weights of the pool
    ///@param quantAMMBaseInterpolationDetails the time variables used for interpolation
    ///@param assets the assets of the pool
    ///@dev this would be more populated for v2 of the pool but the structure is kept for other areas
    struct QuantAMMBaseGetWeightData {
        QuantAMMBaseInterpolationVariables quantAMMBaseInterpolationDetails;
        address[] assets;
    }

    /// @notice Settings needed to create and initialise a pool
    /// @param assets the assets of the pool
    /// @param rule the rule to use for the pool
    /// @param oracles the oracles to use for the pool. [asset oracle][backup oracles for that asset]
    /// @param updateInterval the time between updates
    /// @param lambda the decay parameter for the rule
    /// @param epsilonMax the maximum allowed delta for a weight update
    /// @param absoluteWeightGuardRail the maximum allowed absolute weight allowed
    /// @param maxTradeSizeRatio the maximum trade size allowed as a fraction of the pool
    /// @param ruleParameters the parameters for the rule
    /// @param poolManager the address of the pool manager
    struct PoolSettings {
        IERC20[] assets;
        IUpdateRule rule;
        address[][] oracles;
        uint16 updateInterval;
        uint64[] lambda;
        uint64 epsilonMax;
        uint64 absoluteWeightGuardRail;
        uint64 maxTradeSizeRatio;
        int256[][] ruleParameters;
        address poolManager;
    }

    /// @notice function called to set weights and weight block multipliers
    /// @param _weights the weights to set that sum to 1
    /// @param _poolAddress the address of the pool to set the weights for
    /// @param _lastInterpolationTimePossible the last time that the weights can be updated given the block multiplier before one weight hits the guardrail
    function setWeights(
        int256[] calldata _weights,
        address _poolAddress,
        uint40 _lastInterpolationTimePossible
    ) external;
    
    /// @notice get pool details such as strategy name and description
    /// @param category the category of detail
    /// @param name the name of the detail to be retrieved
    function getPoolDetail(string memory category, string memory name) external view returns (string memory, string memory);

    /// @notice the acceptable number of blocks behind the current that an oracle value can be
    function getOracleStalenessThreshold() external view returns (uint);

    ///@notice returns the normalized weights of the pool for the current block
    function getNormalizedWeights() external view returns (uint256[] memory);
    
    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic QuantAMM weighted pool parameters
     */
    function getQuantAMMWeightedPoolDynamicData() external view returns (QuantAMMWeightedPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable weighted pool parameters
     */
    function getQuantAMMWeightedPoolImmutableData() external view returns (QuantAMMWeightedPoolImmutableData memory data);

    /// @notice this is to update the runner for the pool. This is for hotfixes and is timelock protected.
    function setUpdateWeightRunnerAddress(address _updateWeightRunner) external;
}
