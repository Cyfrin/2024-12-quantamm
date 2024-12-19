pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { QuantAMMWeightedPool } from "../../contracts/QuantAMMWeightedPool.sol";
import { QuantAMMWeightedPoolFactory } from "../../contracts/QuantAMMWeightedPoolFactory.sol";
import { QuantAMMWeightedPoolContractsDeployer } from "./utils/QuantAMMWeightedPoolContractsDeployer.sol";
import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { OracleWrapper } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";
import { MockUpdateWeightRunner } from "../../contracts/mock/MockUpdateWeightRunner.sol";
import { MockMomentumRule } from "../../contracts/mock/mockRules/MockMomentumRule.sol";
import { MockChainlinkOracle } from "../../contracts/mock/MockChainlinkOracles.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";

contract QuantAMMWeightedPoolGenericFuzzer is QuantAMMWeightedPoolContractsDeployer, BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    //@audit taken from QuantAMMWeightedPool
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    // Maximum swap fee of 10%
    uint64 public constant _MAX_SWAP_FEE_PERCENTAGE = 10e16;

    QuantAMMWeightedPoolFactory internal quantAMMWeightedPoolFactory;

    //@audit previous fuzz test was only testing a 20% change (0.125 goes to 0.15 for one asset, and 0.1 for another asset)
    // by shifting weights between min and max, we try to cover the edge cases with maximum/minimum weights
    int256 private constant _NUM_TOKENS = 8; // num tokens
    uint256 private constant _INTERPOLATION_TIME = 5; // 5 seconds - guard rail can be hit
    uint256 private constant _ORACLE_STALENESS_THRESHOLD = 3600; // 1 hour
    uint64 private constant _ABSOLUTE_WEIGHT_GUARD_RAIL = 0.01e18; // 1% guard rail
    uint64 private constant _EPSILON_MAX = 0.01e18; // 1% epsilon max
    uint64 private constant _MAX_TRADE_SIZE_RATIO = 0.01e18; // 1% max trade size ratio
    int256 private constant _MIN_WEIGHT = int256(uint256(_ABSOLUTE_WEIGHT_GUARD_RAIL)); // 0.01e18
    int256 private constant _MAX_WEIGHT =
        1e18 - (int256(_NUM_TOKENS) - 1) * int256(uint256(_ABSOLUTE_WEIGHT_GUARD_RAIL)); // 1e18- (8-1) * 0.01e18 = 0.93e18
    uint16 private constant _UPDATE_INTERVAL = 60; // 60 seconds

    uint64 private constant _LAMBDA = 0.2e18; // 20% lambda
    int256 private constant _KAPPA = 0.2e18; // 20% kappa

    int256 private constant _DEFAULT_WEIGHT = 0.125e18; // 12.5% default weight
    int256 private constant _DEFAULT_MULTIPLIER = 0.001e18; // 0.1% default multiplier

    //@audit taken from WeightedMath.sol
    uint256 private constant _MAX_INVARIANT_RATIO = 300e16; // 300%
    uint256 private constant _MIN_INVARIANT_RATIO = 70e16; // 70%

    //@audit taken from WeightedMath.sol for Swap limits
    uint256 internal constant _MAX_IN_RATIO = 30e16; // 30%
    uint256 internal constant _MAX_OUT_RATIO = 30e16; // 30%

    struct TestParam {
        //@audit convention for struct is camel case starting with capital letter
        uint index;
        int256 weight;
        int256 multiplier;
    }

    struct FuzzParams {
        int256 firstWeight;
        int256 secondWeight;
        int256 firstMultiplier;
        int256 secondMultiplier;
        int256 otherMultiplier; // multiplier for all other weights
        uint256 interpolationTime; // time at which we are doing the swap
        uint256 numTokens;
        uint256 delay;
        PoolFuzzParams poolParams;
        RuleFuzzParams ruleParams;
        BalanceFuzzParams balanceParams;
    }

    struct PoolFuzzParams {
        uint64 lambda;
        uint64 maxSwapfee;
        uint64 epsilonMax;
        uint64 absoluteWeightGuardRail;
        uint64 maxTradeSizeRatio;
        uint16 updateInterval;
    }

    struct RuleFuzzParams {
        uint8 ruleType; // 0 - momentum rule, 1 - anti momentum rule, 2 - min variance rule, 4 - power channel rule
        int256 kappa;
    }

    struct BalanceFuzzParams {
        uint256 balance0;
        uint256 balance1;
        uint256 balance2;
        uint256 balance3;
        uint256 balance4;
        uint256 balance5;
        uint256 balance6;
        uint256 balance7;
    }

    struct LiquidityFuzzParams {
        uint256 tokenIndex;
        uint256 invariantRatio;
    }

    struct SwapFuzzParams {
        uint256 exactIn;
        uint256 exactOut;
    }

    struct VariationTestVariables {
        int256[] newWeights;
        uint256[] testUint256;
        uint256[] balances;
        TestParam firstWeight;
        TestParam secondWeight;
        TestParam otherWeights;
        QuantAMMWeightedPoolFactory.NewPoolParams params;
        PoolSwapParams swapParams;
        IQuantAMMWeightedPool.QuantAMMWeightedPoolDynamicData dynamicData;
        IQuantAMMWeightedPool.QuantAMMWeightedPoolImmutableData immutableData;
    }

    function setUp() public override {
        int216 fixedValue = 1000;
        uint delay = 3600;

        super.setUp();
        (address ownerLocal, address addr1Local, address addr2Local) = (vm.addr(1), vm.addr(2), vm.addr(3));
        owner = ownerLocal;
        addr1 = addr1Local;
        addr2 = addr2Local;
        // Deploy UpdateWeightRunner contract
        vm.startPrank(owner);
        updateWeightRunner = new MockUpdateWeightRunner(owner, addr2, false); //@note owner = vault admin, addr2 = eth oracle

        chainlinkOracle = _deployOracle(fixedValue, delay);

        updateWeightRunner.addOracle(OracleWrapper(chainlinkOracle));

        vm.stopPrank();

        quantAMMWeightedPoolFactory = deployQuantAMMWeightedPoolFactory(
            IVault(address(vault)),
            365 days, //@note pause window is setup at 365 days
            "Factory v1",
            "Pool v1"
        );
        vm.label(address(quantAMMWeightedPoolFactory), "quantamm weighted pool factory");
    }

    function _getTokens(uint256 numTokens) internal view returns (IERC20[] memory) {
        IERC20[] memory tokens_ = new IERC20[](numTokens);
        require(numTokens > 1 && numTokens <= 8, "Atleast 2 tokens and at max 8 tokens");

        tokens_[0] = IERC20(address(dai));
        tokens_[1] = IERC20(address(usdc));

        if (numTokens > 2) {
            tokens_[2] = IERC20(address(weth));
        }
        if (numTokens > 3) {
            tokens_[3] = IERC20(address(wsteth));
        }
        if (numTokens > 4) {
            tokens_[4] = IERC20(address(veBAL));
        }
        if (numTokens > 5) {
            tokens_[5] = IERC20(address(waDAI));
        }
        if (numTokens > 6) {
            tokens_[6] = IERC20(address(usdt));
        }
        if (numTokens > 7) {
            tokens_[7] = IERC20(address(waUSDC));
        }
        return tokens_;
    }

    function _createRule(RuleFuzzParams memory ruleParams) internal returns (IUpdateRule, int256[][] memory) {
        //@note for now - hardcoded. will change this to a dynamic rule later
        MockMomentumRule momentumRule = new MockMomentumRule(owner);

        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        parameters[0][0] = ruleParams.kappa;

        return (IUpdateRule(address(momentumRule)), parameters);
    }

    function _createPoolParams(
        uint256 numTokens,
        PoolFuzzParams memory poolParams,
        RuleFuzzParams memory ruleParams
    ) internal returns (QuantAMMWeightedPoolFactory.NewPoolParams memory) {
        // Create base params first
        QuantAMMWeightedPoolFactory.NewPoolParams memory baseParams = _createBaseParams(
            numTokens,
            poolParams.maxSwapfee
        );

        // Update with pool settings
        baseParams._poolSettings = _createPoolSettings(numTokens, poolParams, ruleParams);

        return baseParams;
    }

    function _createBaseParams(
        uint256 numTokens,
        uint64 maxSwapFee
    ) internal view returns (QuantAMMWeightedPoolFactory.NewPoolParams memory) {
        PoolRoleAccounts memory roleAccounts;
        IERC20[] memory poolTokens = _getTokens(numTokens);

        (uint256[] memory initialWeightsUint, int256[] memory initialWeights) = _createInitialWeights(numTokens);

        return
            QuantAMMWeightedPoolFactory.NewPoolParams({
                name: "Pool With Donation",
                symbol: "PwD",
                tokens: vault.buildTokenConfig(poolTokens),
                normalizedWeights: initialWeightsUint,
                roleAccounts: roleAccounts,
                swapFeePercentage: maxSwapFee,
                poolHooksContract: address(0),
                enableDonation: true,
                disableUnbalancedLiquidity: false,
                salt: keccak256(abi.encodePacked(uint256(1))),
                _initialWeights: initialWeights,
                _poolSettings: IQuantAMMWeightedPool.PoolSettings({
                    assets: new IERC20[](0),
                    rule: IUpdateRule(address(0)),
                    oracles: new address[][](0),
                    updateInterval: 0,
                    lambda: new uint64[](0),
                    epsilonMax: 0,
                    absoluteWeightGuardRail: 0,
                    maxTradeSizeRatio: 0,
                    ruleParameters: new int256[][](0),
                    poolManager: address(0)
                }),
                _initialMovingAverages: initialWeights,
                _initialIntermediateValues: initialWeights,
                _oracleStalenessThreshold: 3600,
                poolRegistry: 0,
                poolDetails: new string[][](0)
            });
    }

    function _createInitialWeights(
        uint256 numTokens
    ) internal pure returns (uint256[] memory initialWeightsUint, int256[] memory initialWeights) {
        initialWeightsUint = new uint256[](numTokens);
        initialWeights = new int256[](numTokens);

        int256 weight = 1e18 / int256(numTokens);

        for (uint i; i < numTokens; i++) {
            if (i == numTokens - 1) {
                // Account for odd number of tokens by adjusting final weight
                weight = 1e18 - (int256(numTokens - 1) * weight);
            }

            initialWeights[i] = weight;
            initialWeightsUint[i] = uint256(weight);
        }

        return (initialWeightsUint, initialWeights);
    }

    function _createPoolSettings(
        uint256 numTokens,
        PoolFuzzParams memory poolParams,
        RuleFuzzParams memory ruleParams
    ) internal returns (IQuantAMMWeightedPool.PoolSettings memory) {
        (IUpdateRule rule, int256[][] memory ruleParameters) = _createRule(ruleParams);

        uint64[] memory lambdas = new uint64[](1);
        lambdas[0] = poolParams.lambda;

        address[][] memory oracles = new address[][](1);
        oracles[0] = new address[](1);
        oracles[0][0] = address(chainlinkOracle);

        return
            IQuantAMMWeightedPool.PoolSettings({
                assets: new IERC20[](numTokens),
                rule: rule,
                oracles: oracles,
                updateInterval: poolParams.updateInterval,
                lambda: lambdas,
                epsilonMax: poolParams.epsilonMax,
                absoluteWeightGuardRail: poolParams.absoluteWeightGuardRail,
                maxTradeSizeRatio: poolParams.maxTradeSizeRatio,
                ruleParameters: ruleParameters,
                poolManager: address(0)
            });
    }

    function _setupVariables(
        VariationTestVariables memory variables,
        uint i,
        uint j,
        FuzzParams memory params
    ) internal pure {
        variables.firstWeight.index = i;
        variables.secondWeight.index = j;
        variables.params.salt = keccak256(abi.encodePacked(params.delay, "i", i, "_", "j_", j));

        int256 minWeight = int256(uint256(params.poolParams.absoluteWeightGuardRail));
        int256 maxWeight = 1e18 - (int256(params.numTokens - 1) * minWeight);

        // Add bounds for first weight
        variables.firstWeight.weight = truncateTo32Bit(bound(params.firstWeight, minWeight, maxWeight));

        int256 maxSecondWeight = 1e18 - variables.firstWeight.weight - (minWeight * int256(params.numTokens - 2));
        if (maxSecondWeight > maxWeight) maxSecondWeight = maxWeight;
        // Add bound for second weight
        variables.secondWeight.weight = truncateTo32Bit(bound(params.secondWeight, minWeight, maxSecondWeight));

        // Bound multiplier to safe range over interpolation time
        // default multiplier is designed to traverse min-> max -> this is causing an underflow in calculateBlockNormalisedWeight
        // @audit to prevent this, we are  restricting multiplier to a safe range
        //@audit truncating to 32 bit to make it consistent with the unpacking logic in the contract
        variables.firstWeight.multiplier = truncateTo32Bit(
            bound(
                params.firstMultiplier,
                (minWeight - variables.firstWeight.weight) / int256(params.interpolationTime),
                (maxWeight - variables.firstWeight.weight) / int256(params.interpolationTime)
            )
        );

        // Same for second weight
        variables.secondWeight.multiplier = truncateTo32Bit(
            bound(
                params.secondMultiplier,
                (minWeight - variables.secondWeight.weight) / int256(params.interpolationTime),
                (maxWeight - variables.secondWeight.weight) / int256(params.interpolationTime)
            )
        );

        // @audit for other tokens, calculate safe range by using the residual weight
        int256 otherWeight = params.numTokens == 2
            ? int256(0)
            : truncateTo32Bit(
                (1e18 - variables.firstWeight.weight - variables.secondWeight.weight) / int256(params.numTokens - 2)
            );
        int256 otherMultiplier = _min(variables.secondWeight.multiplier, variables.firstWeight.multiplier);

        otherMultiplier = params.numTokens == 2
            ? int256(0)
            : truncateTo32Bit(
                bound(
                    otherMultiplier,
                    (minWeight - otherWeight) / int256(params.interpolationTime),
                    (maxWeight - otherWeight) / int256(params.interpolationTime)
                )
            );

        // store them in other weights as we need to use them later
        variables.otherWeights.weight = otherWeight;
        variables.otherWeights.multiplier = otherMultiplier;

        variables.newWeights = _getDefaultWeightAndMultiplierForRemainingTokens(
            variables.firstWeight,
            variables.secondWeight,
            variables.otherWeights,
            params.numTokens
        );

        variables.balances = _getBalances(params.numTokens, params.balanceParams);
    }

    function _getBalances(
        uint256 numTokens,
        BalanceFuzzParams memory balanceParams
    ) internal pure returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](numTokens);

        balances[0] = bound(balanceParams.balance0, 100e18, type(uint128).max);
        balances[1] = bound(balanceParams.balance1, 100e18, type(uint128).max);

        if (numTokens > 2) {
            balances[2] = bound(balanceParams.balance2, 100e18, type(uint128).max);
        }
        if (numTokens > 3) {
            balances[3] = bound(balanceParams.balance3, 100e18, type(uint128).max);
        }

        if (numTokens > 4) {
            balances[4] = bound(balanceParams.balance4, 100e18, type(uint128).max);
        }

        if (numTokens > 5) {
            balances[5] = bound(balanceParams.balance5, 100e18, type(uint128).max);
        }

        if (numTokens > 6) {
            balances[6] = bound(balanceParams.balance6, 100e18, type(uint128).max);
        }

        if (numTokens > 7) {
            balances[7] = bound(balanceParams.balance7, 100e18, type(uint128).max);
        }

        return balances;
    }

    function _getDefaultWeightAndMultiplierForRemainingTokens(
        TestParam memory firstWeightParam,
        TestParam memory secondWeightParam,
        TestParam memory otherWeightParams,
        uint256 numTokens
    ) internal pure returns (int256[] memory weights) {
        weights = new int256[](uint256(numTokens * 2));

        // Set weights
        for (uint i = 0; i < uint256(numTokens); i++) {
            if (i == firstWeightParam.index) {
                weights[i] = firstWeightParam.weight;
            } else if (i == secondWeightParam.index) {
                weights[i] = secondWeightParam.weight;
            } else {
                weights[i] = otherWeightParams.weight;
            }
            // Set multipliers
            weights[i + uint256(numTokens)] = i == firstWeightParam.index
                ? firstWeightParam.multiplier
                : (i == secondWeightParam.index ? secondWeightParam.multiplier : otherWeightParams.multiplier);
        }
    }

    function _calculateInterpolatedWeight(TestParam memory param, uint256 delay) internal pure returns (uint256) {
        int256 multiplierScaled18 = param.multiplier * 1e18;
        if (param.multiplier > 0) {
            return uint256(param.weight) + FixedPoint.mulDown(uint256(multiplierScaled18), delay);
        } else {
            return uint256(param.weight) - FixedPoint.mulUp(uint256(-multiplierScaled18), delay);
        }
    }

    function truncateTo32Bit(int256 value) internal pure returns (int256) {
        return (value / 1e9) * 1e9;
    }

    function _logFuzzParams(
        FuzzParams memory params,
        bool logPoolParams,
        bool logRuleParams,
        bool logBalanceParams
    ) internal view {
        // top level fuzz params
        console.logString(string.concat("Interpolation time: ", vm.toString(params.interpolationTime)));
        console.logString(string.concat("Delay: ", vm.toString(params.delay)));
        console.logString(string.concat("Number of Tokens: ", vm.toString(params.numTokens)));

        if (logPoolParams) {
            console.logString(string.concat("Lambda", vm.toString(params.poolParams.lambda)));
            console.logString(string.concat("Max Swap Fee", vm.toString(params.poolParams.maxSwapfee)));
            console.logString(string.concat("Epsilon Max", vm.toString(params.poolParams.epsilonMax)));
            console.logString(
                string.concat("Abs Weight Guard Rail", vm.toString(params.poolParams.absoluteWeightGuardRail))
            );
            console.logString(string.concat("Max Trade Size Ratio", vm.toString(params.poolParams.maxTradeSizeRatio)));
            console.logString(string.concat("Update Interval", vm.toString(params.poolParams.updateInterval)));
        }

        if (logRuleParams) {
            console.logString(string.concat("Rule Type", vm.toString(params.ruleParams.ruleType)));
            console.logString(string.concat("Kappa", vm.toString(params.ruleParams.kappa)));
        }
        if (logBalanceParams) {
            console.logString(string.concat("Balance 0", vm.toString(params.balanceParams.balance0)));
            console.logString(string.concat("Balance 1", vm.toString(params.balanceParams.balance1)));
            console.logString(string.concat("Balance 2", vm.toString(params.balanceParams.balance2)));
            console.logString(string.concat("Balance 3", vm.toString(params.balanceParams.balance3)));
            console.logString(string.concat("Balance 4", vm.toString(params.balanceParams.balance4)));
            console.logString(string.concat("Balance 5", vm.toString(params.balanceParams.balance5)));
            console.logString(string.concat("Balance 6", vm.toString(params.balanceParams.balance6)));
            console.logString(string.concat("Balance 7", vm.toString(params.balanceParams.balance7)));
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _min(int256 a, int256 b) private pure returns (int256) {
        return a < b ? a : b;
    }

    function _testGetNormalizedWeights(FuzzParams memory params) internal {
        uint40 timestamp = uint40(block.timestamp);
        VariationTestVariables memory variables;
        variables.firstWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.secondWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.otherWeights = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);

        // create pool params
        variables.params = _createPoolParams(params.numTokens, params.poolParams, params.ruleParams);

        address quantAMMWeightedPool = quantAMMWeightedPoolFactory.createWithoutArgs(variables.params); //@note new pool params

        uint expectedDelay = params.delay;
        if (params.delay > params.interpolationTime) {
            expectedDelay = params.interpolationTime;
        }
        for (uint i = 0; i < params.numTokens; i++) {
            for (uint j = 0; j < params.numTokens; j++) {
                if (i != j) {
                    vm.warp(timestamp);
                    _setupVariables(variables, i, j, params);

                    vm.prank(address(updateWeightRunner));
                    QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
                        variables.newWeights,
                        quantAMMWeightedPool,
                        uint40(timestamp + params.interpolationTime)
                    );

                    if (params.delay > 0) {
                        vm.warp(timestamp + params.delay);
                    }

                    variables.testUint256 = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();
                    console.log("index i", i);
                    console.log("index j", j);
                    console.logString(string.concat("first weight: ", vm.toString(variables.firstWeight.weight)));
                    console.logString(string.concat("second weight: ", vm.toString(variables.secondWeight.weight)));
                    console.logString(string.concat("other weight: ", vm.toString(variables.otherWeights.weight)));

                    console.logString(
                        string.concat("first multiplier: ", vm.toString(variables.firstWeight.multiplier))
                    );
                    console.logString(
                        string.concat("second multiplier: ", vm.toString(variables.secondWeight.multiplier))
                    );
                    console.logString(
                        string.concat("other multiplier: ", vm.toString(variables.otherWeights.multiplier))
                    );
                    console.log("expected delay", expectedDelay);

                    for (uint k = 0; k < params.numTokens; k++) {
                        if (k == variables.firstWeight.index) {
                            if (variables.firstWeight.multiplier > 0) {
                                assertEq(
                                    variables.testUint256[k],
                                    uint256(variables.firstWeight.weight) +
                                        uint256(variables.firstWeight.multiplier) *
                                        expectedDelay
                                );
                            } else {
                                assertEq(
                                    variables.testUint256[k],
                                    uint256(variables.firstWeight.weight) -
                                        uint256(-variables.firstWeight.multiplier) *
                                        expectedDelay
                                );
                            }
                        } else if (k == variables.secondWeight.index) {
                            if (variables.secondWeight.multiplier > 0) {
                                assertEq(
                                    variables.testUint256[k],
                                    uint256(variables.secondWeight.weight) +
                                        uint256(variables.secondWeight.multiplier) *
                                        expectedDelay
                                );
                            } else {
                                assertEq(
                                    variables.testUint256[k],
                                    uint256(variables.secondWeight.weight) -
                                        uint256(-variables.secondWeight.multiplier) *
                                        expectedDelay
                                );
                            }
                        } else {
                            if (variables.otherWeights.multiplier > 0) {
                                assertEq(
                                    variables.testUint256[k],
                                    uint256(variables.otherWeights.weight) +
                                        uint256(variables.otherWeights.multiplier) *
                                        expectedDelay
                                );
                            } else {
                                assertEq(
                                    variables.testUint256[k],
                                    uint256(variables.otherWeights.weight) -
                                        uint256(-variables.otherWeights.multiplier) *
                                        expectedDelay
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    function _testGetDynamicData(FuzzParams memory params) internal {
        uint40 timestamp = uint40(block.timestamp);
        VariationTestVariables memory variables;
        variables.firstWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.secondWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.otherWeights = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);

        // create pool params
        variables.params = _createPoolParams(params.numTokens, params.poolParams, params.ruleParams);

        address quantAMMWeightedPool = quantAMMWeightedPoolFactory.createWithoutArgs(variables.params);

        uint expectedDelay = params.delay;
        if (params.delay > params.interpolationTime) {
            expectedDelay = params.interpolationTime;
        }
        for (uint i = 0; i < params.numTokens; i++) {
            for (uint j = 0; j < params.numTokens; j++) {
                if (i != j) {
                    vm.warp(timestamp);
                    _setupVariables(variables, i, j, params);

                    vm.prank(address(updateWeightRunner));
                    QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
                        variables.newWeights,
                        quantAMMWeightedPool,
                        uint40(timestamp + params.interpolationTime)
                    );

                    if (params.delay > 0) {
                        vm.warp(timestamp + params.delay);
                    }

                    variables.dynamicData = QuantAMMWeightedPool(quantAMMWeightedPool)
                        .getQuantAMMWeightedPoolDynamicData();

                    console.log("index i", i);
                    console.log("index j", j);
                    console.logString(string.concat("first weight: ", vm.toString(variables.firstWeight.weight)));
                    console.logString(string.concat("second weight: ", vm.toString(variables.secondWeight.weight)));
                    console.logString(string.concat("other weight: ", vm.toString(variables.otherWeights.weight)));

                    console.logString(
                        string.concat("first multiplier: ", vm.toString(variables.firstWeight.multiplier))
                    );
                    console.logString(
                        string.concat("second multiplier: ", vm.toString(variables.secondWeight.multiplier))
                    );
                    console.logString(
                        string.concat("other multiplier: ", vm.toString(variables.otherWeights.multiplier))
                    );
                    console.log("expected delay", expectedDelay);

                    for (uint k = 0; k < params.numTokens; k++) {
                        if (k == variables.firstWeight.index) {
                            assertEq(
                                variables.dynamicData.weightsAtLastUpdateInterval[variables.firstWeight.index],
                                variables.firstWeight.weight
                            );
                            assertEq(
                                variables.dynamicData.weightBlockMultipliers[variables.firstWeight.index],
                                variables.firstWeight.multiplier
                            );
                        } else if (k == variables.secondWeight.index) {
                            assertEq(
                                variables.dynamicData.weightsAtLastUpdateInterval[variables.secondWeight.index],
                                variables.secondWeight.weight
                            );
                            assertEq(
                                variables.dynamicData.weightBlockMultipliers[variables.secondWeight.index],
                                variables.secondWeight.multiplier
                            );
                        } else {
                            assertEq(
                                variables.dynamicData.weightsAtLastUpdateInterval[k],
                                variables.otherWeights.weight
                            );
                            assertEq(
                                variables.dynamicData.weightBlockMultipliers[k],
                                variables.otherWeights.multiplier
                            );
                        }
                    }

                    assertEq(variables.dynamicData.lastUpdateIntervalTime, uint40(timestamp));
                    assertEq(
                        variables.dynamicData.lastInterpolationTimePossible,
                        uint40(timestamp + params.interpolationTime)
                    );
                }
            }
        }
    }

    function _testBalances(FuzzParams memory params, LiquidityFuzzParams memory liquidityParams) internal {
        uint40 timestamp = uint40(block.timestamp);
        VariationTestVariables memory variables;
        variables.firstWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.secondWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.otherWeights = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);

        liquidityParams.tokenIndex = bound(liquidityParams.tokenIndex, 0, params.numTokens - 1);
        liquidityParams.invariantRatio = bound(
            liquidityParams.invariantRatio,
            _MIN_INVARIANT_RATIO,
            _MAX_INVARIANT_RATIO
        );

        variables.params = _createPoolParams(params.numTokens, params.poolParams, params.ruleParams);
        address quantAMMWeightedPool = quantAMMWeightedPoolFactory.createWithoutArgs(variables.params);

        uint expectedDelay = params.delay;
        if (params.delay > params.interpolationTime) {
            expectedDelay = params.interpolationTime;
        }

        for (uint i = 0; i < params.numTokens; i++) {
            for (uint j = 0; j < params.numTokens; j++) {
                if (i != j) {
                    vm.warp(timestamp);
                    _setupVariables(variables, i, j, params);

                    vm.prank(address(updateWeightRunner));
                    QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
                        variables.newWeights,
                        quantAMMWeightedPool,
                        uint40(timestamp + params.interpolationTime)
                    );

                    if (params.delay > 0) {
                        vm.warp(timestamp + params.delay);
                    }
                    console.log("num tokens", params.numTokens);
                    console.log("index i", i);
                    console.log("index j", j);
                    console.logString(string.concat("first weight: ", vm.toString(variables.firstWeight.weight)));
                    console.logString(string.concat("second weight: ", vm.toString(variables.secondWeight.weight)));
                    console.logString(string.concat("other weight: ", vm.toString(variables.otherWeights.weight)));

                    console.logString(
                        string.concat("first multiplier: ", vm.toString(variables.firstWeight.multiplier))
                    );
                    console.logString(
                        string.concat("second multiplier: ", vm.toString(variables.secondWeight.multiplier))
                    );
                    console.logString(
                        string.concat("other multiplier: ", vm.toString(variables.otherWeights.multiplier))
                    );
                    console.log("expected delay", expectedDelay);

                    console.logString(string.concat("token index: ", vm.toString(liquidityParams.tokenIndex)));
                    console.logString(
                        string.concat(
                            "balance for token index",
                            vm.toString(variables.balances[liquidityParams.tokenIndex])
                        )
                    );
                    console.logString(string.concat("invariant ratio", vm.toString(liquidityParams.invariantRatio)));

                    // @audit Calculate this instead of passing it as input
                    uint256 normalizedWeight = _calculateInterpolatedWeight(
                        liquidityParams.tokenIndex == variables.firstWeight.index
                            ? variables.firstWeight
                            : liquidityParams.tokenIndex == variables.secondWeight.index
                            ? variables.secondWeight
                            : variables.otherWeights,
                        expectedDelay
                    );
                    console.logString(string.concat("normalized weight", vm.toString(normalizedWeight)));

                    //Calculate expected balance using WeightedMath formula
                    uint256 expectedBalance = WeightedMath.computeBalanceOutGivenInvariant(
                        variables.balances[liquidityParams.tokenIndex],
                        normalizedWeight,
                        liquidityParams.invariantRatio
                    );

                    uint256 actualBalance = QuantAMMWeightedPool(quantAMMWeightedPool).computeBalance(
                        variables.balances,
                        liquidityParams.tokenIndex,
                        liquidityParams.invariantRatio
                    );
                    assertApproxEqRel(actualBalance, expectedBalance, 1e12); // Allow small relative error
                }
            }
        }
    }

    function _testSwapExactIn(FuzzParams memory params, SwapFuzzParams memory swapParams) internal {
        uint40 timestamp = uint40(block.timestamp);
        VariationTestVariables memory variables;

        variables.firstWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.secondWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.otherWeights = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);

        // create pool params
        variables.params = _createPoolParams(params.numTokens, params.poolParams, params.ruleParams);

        address quantAMMWeightedPool = quantAMMWeightedPoolFactory.createWithoutArgs(variables.params);

        swapParams.exactOut = 0; // this is an exact in swap

        uint expectedDelay = params.delay;
        if (params.delay > params.interpolationTime) {
            expectedDelay = params.interpolationTime;
        }

        for (uint i = 0; i < params.numTokens; i++) {
            for (uint j = 0; j < params.numTokens; j++) {
                if (i != j) {
                    vm.warp(timestamp);
                    _setupVariables(variables, i, j, params);

                    vm.prank(address(updateWeightRunner));
                    QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
                        variables.newWeights,
                        quantAMMWeightedPool,
                        uint40(timestamp + params.interpolationTime)
                    );

                    uint256 maxTradeSize = variables.balances[variables.firstWeight.index].mulDown(
                        _min(_MAX_IN_RATIO, uint256(params.poolParams.maxTradeSizeRatio))
                    );
                    swapParams.exactIn = bound(swapParams.exactIn, 1, maxTradeSize);

                    if (params.delay > 0) {
                        vm.warp(timestamp + params.delay);
                    }

                    variables.swapParams = PoolSwapParams({
                        kind: SwapKind.EXACT_IN,
                        amountGivenScaled18: swapParams.exactIn,
                        balancesScaled18: variables.balances,
                        indexIn: variables.firstWeight.index,
                        indexOut: variables.secondWeight.index,
                        router: address(router),
                        userData: abi.encode(0)
                    });

                    vm.prank(address(vault));
                    uint256 amountOut = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(variables.swapParams);

                    // get the pool weights
                    uint256[] memory poolWeights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

                    // For ExactIn:
                    uint256 expectedAmountOut = WeightedMath.computeOutGivenExactIn(
                        variables.balances[variables.firstWeight.index],
                        poolWeights[variables.firstWeight.index],
                        variables.balances[variables.secondWeight.index],
                        poolWeights[variables.secondWeight.index],
                        swapParams.exactIn
                    );

                    assertApproxEqRel(amountOut, expectedAmountOut, 1e12); // Allow very small relative error
                }
            }
        }
    }

    function _testSwapExactOut(FuzzParams memory params, SwapFuzzParams memory swapParams) internal {
        uint40 timestamp = uint40(block.timestamp);
        VariationTestVariables memory variables;

        variables.firstWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.secondWeight = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);
        variables.otherWeights = TestParam(0, _DEFAULT_WEIGHT, _DEFAULT_MULTIPLIER);

        // create pool params
        variables.params = _createPoolParams(params.numTokens, params.poolParams, params.ruleParams);

        address quantAMMWeightedPool = quantAMMWeightedPoolFactory.createWithoutArgs(variables.params);

        swapParams.exactIn = 0; // this is an exact out swap

        uint expectedDelay = params.delay;
        if (params.delay > params.interpolationTime) {
            expectedDelay = params.interpolationTime;
        }

        for (uint i = 0; i < params.numTokens; i++) {
            for (uint j = 0; j < params.numTokens; j++) {
                if (i != j) {
                    vm.warp(timestamp);
                    _setupVariables(variables, i, j, params);

                    vm.prank(address(updateWeightRunner));
                    QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
                        variables.newWeights,
                        quantAMMWeightedPool,
                        uint40(timestamp + params.interpolationTime)
                    );

                    uint256 maxTradeSize = variables.balances[variables.secondWeight.index].mulDown(
                        _min(_MAX_IN_RATIO, uint256(params.poolParams.maxTradeSizeRatio))
                    );
                    swapParams.exactOut = bound(swapParams.exactOut, 1, maxTradeSize);

                    if (params.delay > 0) {
                        vm.warp(timestamp + params.delay);
                    }

                    variables.swapParams = PoolSwapParams({
                        kind: SwapKind.EXACT_OUT,
                        amountGivenScaled18: swapParams.exactOut,
                        balancesScaled18: variables.balances,
                        indexIn: variables.firstWeight.index,
                        indexOut: variables.secondWeight.index,
                        router: address(router),
                        userData: abi.encode(0)
                    });
                    vm.prank(address(vault));
                    uint256 amountIn = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(variables.swapParams);

                    uint256[] memory poolWeights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

                    // For ExactOut:
                    uint256 expectedAmountIn = WeightedMath.computeInGivenExactOut(
                        variables.balances[variables.firstWeight.index],
                        poolWeights[variables.firstWeight.index],
                        variables.balances[variables.secondWeight.index],
                        poolWeights[variables.secondWeight.index],
                        swapParams.exactOut
                    );

                    assertApproxEqRel(amountIn, expectedAmountIn, 1e12);
                }
            }
        }
    }

    /**** -----------------------------------------------------------------------*****/

    /******* ------------------Tests -------------------------------------- *********/

    //@audit except for delay, other fuzzing param bounds are configured in setVariables
    //@note this is similar to the testGetNormalizedWeightsInitial_Fuzz - starting at a base level and slowly expanding fuzz envelope
    //@note this test uses variable numTokens and variable balances
    function testGetNormalizedWeightsInitial_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay to 0
        params.delay = 0;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    //@audit this test checks the interpolation at times < interpoliation time
    //@note again numTokens and balances are extra fuzz params here
    function testGetNormalizedWeightsNBlocksAfter_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    function testGetNormalizedWeightsAfterLimit_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay after interpolation time
        params.delay = bound(params.delay, _INTERPOLATION_TIME + 1, type(uint40).max);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    // uses a dynamic interpolation time
    function testGetNormalizedWeightsNBlocksAfter_DynamicInterpolationTime_Fuzz_Generic(
        FuzzParams memory params
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    function testGetNormalizedWeightsAfterLimit_DynamicInterpolationTime_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, params.interpolationTime + 1, type(uint40).max);

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    // use a dynamic update interval and dynamic interpolation time
    function testGetNormalizedWeightsNBlocksAfter_DynamicIntervalAndInterpolationTime_Fuzz_Generic(
        FuzzParams memory params
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = uint16(bound(params.poolParams.updateInterval, 1, 7 * 86400)); // 7 days

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    function testGetNormalizedWeightsAfterLimit_DynamicIntervalAndInterpolationTime_Fuzz_Generic(
        FuzzParams memory params
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = uint16(bound(params.poolParams.updateInterval, 1, 7 * 86400)); // 7 days

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, params.interpolationTime + 1, type(uint40).max);

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetNormalizedWeights(params);
    }

    // change the abs weight guard rail
    function testGetNormalizedWeightsNBlocksAfter_GuardRail_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, _ABSOLUTE_WEIGHT_GUARD_RAIL, 1e18 / params.numTokens - 1)
        );

        _testGetNormalizedWeights(params);
    }

    function testGetNormalizedWeightsAfterLimit_GuardRail_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay after interpolation time
        params.delay = bound(params.delay, params.interpolationTime + 1, type(uint40).max);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, _ABSOLUTE_WEIGHT_GUARD_RAIL, 1e18 / params.numTokens - 1)
        );

        _testGetNormalizedWeights(params);
    }

    function testGetDynamicDataWeightsInitial_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay to 0
        params.delay = 0;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetDynamicData(params);
    }

    function testGetDynamicDataWeightsNBlocksAfter_Fuzz_Generic(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetDynamicData(params);
    }

    function testGetDynamicDataWeightsAfterLimit_Fuzz(FuzzParams memory params) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay after interpolation time
        params.delay = bound(params.delay, _INTERPOLATION_TIME + 1, type(uint40).max);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);
        _testGetDynamicData(params);
    }

    function testGetDynamicDataWeightsNBlocksAfter_DynamicInterpolationTime_Fuzz_Generic(
        FuzzParams memory params
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        params.numTokens = bound(params.numTokens, 2, 8);

        _testGetDynamicData(params);
    }

    function testGetDynamicDataWeightsNBlocksAfter_DynamicIntervalAndInterpolationTime_Fuzz_Generic(
        FuzzParams memory params
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = uint16(bound(params.poolParams.updateInterval, 1, 7 * 86400)); // 7 days

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        params.numTokens = bound(params.numTokens, 2, 8);
        _testGetDynamicData(params);
    }

    function testGetDynamicDataWeightsAfterLimit_DynamicIntervalAndInterpolationTime_Fuzz(
        FuzzParams memory params
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = uint16(bound(params.poolParams.updateInterval, 1, 7 * 86400)); // 7 days

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        // fix delay upto interpolation time
        params.delay = bound(params.delay, params.interpolationTime + 1, type(uint40).max);

        params.numTokens = bound(params.numTokens, 2, 8);
        _testGetDynamicData(params);
    }

    //the other tests go through individual use cases, this makes sure no combo of weight in and out makes a difference
    function testBalancesInitial_Fuzz_Generic(
        FuzzParams memory params,
        LiquidityFuzzParams memory liquidityParams
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay to 0
        params.delay = 0;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.numTokens = bound(params.numTokens, 2, 8);
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, 3e16, 1e18 / params.numTokens - 1)
        );

        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        _testBalances(params, liquidityParams);
    }

    function testBalancesNBlocksAfter_Fuzz_Generic(
        FuzzParams memory params,
        LiquidityFuzzParams memory liquidityParams
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay upto interpolation time
        params.delay = bound(params.delay, 1, params.interpolationTime);

        params.numTokens = bound(params.numTokens, 2, 8);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, 3e16, 1e18 / params.numTokens - 1)
        );
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        console.log("num tokens", params.numTokens);
        console.logString(
            string.concat("absolute weight guard rail: ", vm.toString(params.poolParams.absoluteWeightGuardRail))
        );

        _testBalances(params, liquidityParams);
    }

    function testBalancesAfterLimit_Fuzz_Generic(
        FuzzParams memory params,
        LiquidityFuzzParams memory liquidityParams
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        params.numTokens = bound(params.numTokens, 2, 8);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, 3e16, 1e18 / params.numTokens - 1)
        );
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        console.log("num tokens", params.numTokens);
        console.logString(
            string.concat("absolute weight guard rail: ", vm.toString(params.poolParams.absoluteWeightGuardRail))
        );

        params.delay = bound(params.delay, _INTERPOLATION_TIME + 1, type(uint40).max);
        _testBalances(params, liquidityParams);
    }

    //the other tests go through individual use cases, this makes sure no combo of weight in and out makes a difference
    function testSwapExactInInitial_Fuzz_Generic(FuzzParams memory params, SwapFuzzParams memory swapParams) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay to 0
        params.delay = 0;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testSwapExactIn(params, swapParams);
    }

    function testSwapExactInNBlocksAfter_Fuzz_Generic(
        FuzzParams memory params,
        SwapFuzzParams memory swapParams
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        params.delay = bound(params.delay, 1, _INTERPOLATION_TIME);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testSwapExactIn(params, swapParams);
    }

    function testSwapExactInAfterLimit_Fuzz_Generic(FuzzParams memory params, SwapFuzzParams memory swapParams) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        params.delay = bound(params.delay, _INTERPOLATION_TIME + 1, type(uint40).max);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testSwapExactIn(params, swapParams);
    }

    function testSwapExactInNBlocksAfter_Expanded_Fuzz_Generic(
        FuzzParams memory params,
        RuleFuzzParams memory ruleParams,
        SwapFuzzParams memory swapParams
    ) public {
        // construct momentum rule with default params
        ruleParams.ruleType = 0;
        ruleParams.kappa = int256(bound(ruleParams.kappa, 0.01e18, 1e18));
        params.ruleParams = ruleParams;
        // fuzz update interval
        params.poolParams.updateInterval = uint16(bound(params.poolParams.updateInterval, 1, 7 * 86400)); // 7 days

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        params.delay = bound(params.delay, 1, params.interpolationTime);

        // fix pool params to default
        params.poolParams.epsilonMax = uint64(bound(params.poolParams.maxSwapfee, 1e16, 1e18 - 1));
        params.poolParams.lambda = uint64(bound(params.poolParams.lambda, 1, 1e18 - 1));
        params.poolParams.maxSwapfee = uint64(
            bound(params.poolParams.maxSwapfee, _MIN_SWAP_FEE_PERCENTAGE, _MAX_SWAP_FEE_PERCENTAGE)
        );
        params.poolParams.maxTradeSizeRatio = uint64(bound(params.poolParams.maxTradeSizeRatio, 1e16, 30e16));
        params.numTokens = bound(params.numTokens, 2, 8);
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, 3e16, 1e18 / params.numTokens - 1)
        );

        _testSwapExactIn(params, swapParams);
    }

    // //the other tests go through individual use cases, this makes sure no combo of weight in and out makes a difference
    function testSwapExactOutInitial_Fuzz_Generic(FuzzParams memory params, SwapFuzzParams memory swapParams) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        // fix delay to 0
        params.delay = 0;

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);

        _testSwapExactOut(params, swapParams);
    }

    function testSwapExactOutNBlocksAfter_Fuzz_Generic(
        FuzzParams memory params,
        SwapFuzzParams memory swapParams
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        params.delay = bound(params.delay, 1, _INTERPOLATION_TIME);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);
        _testSwapExactOut(params, swapParams);
    }

    function testSwapExactOutAfterLimit_Fuzz_Generic(
        FuzzParams memory params,
        SwapFuzzParams memory swapParams
    ) public {
        // construct momentum rule with default params
        RuleFuzzParams memory ruleParams = RuleFuzzParams({
            ruleType: 0, // momentum rule
            kappa: _KAPPA
        });
        params.ruleParams = ruleParams;

        // fix interpolation time to default
        params.interpolationTime = _INTERPOLATION_TIME;

        params.delay = bound(params.delay, _INTERPOLATION_TIME + 1, type(uint40).max);

        // fix pool params to default
        params.poolParams.epsilonMax = _EPSILON_MAX;
        params.poolParams.lambda = _LAMBDA;
        params.poolParams.maxSwapfee = _MAX_SWAP_FEE_PERCENTAGE;
        params.poolParams.absoluteWeightGuardRail = _ABSOLUTE_WEIGHT_GUARD_RAIL;
        params.poolParams.maxTradeSizeRatio = _MAX_TRADE_SIZE_RATIO;
        params.poolParams.updateInterval = _UPDATE_INTERVAL;

        params.numTokens = bound(params.numTokens, 2, 8);
        _testSwapExactOut(params, swapParams);
    }

    function testSwapExactOutNBlocksAfter_Expanded_Fuzz_Generic(
        FuzzParams memory params,
        RuleFuzzParams memory ruleParams,
        SwapFuzzParams memory swapParams
    ) public {
        // construct momentum rule with default params
        ruleParams.ruleType = 0;
        ruleParams.kappa = int256(bound(ruleParams.kappa, 0.01e18, 1e18));
        params.ruleParams = ruleParams;
        // fuzz update interval
        params.poolParams.updateInterval = uint16(bound(params.poolParams.updateInterval, 1, 7 * 86400)); // 7 days

        // fuzz the interpolation time
        params.interpolationTime = bound(params.interpolationTime, 1, params.poolParams.updateInterval);

        params.delay = bound(params.delay, 1, params.interpolationTime);

        // fix pool params to default
        params.poolParams.epsilonMax = uint64(bound(params.poolParams.maxSwapfee, 1e16, 1e18 - 1));
        params.poolParams.lambda = uint64(bound(params.poolParams.lambda, 1, 1e18 - 1));
        params.poolParams.maxSwapfee = uint64(
            bound(params.poolParams.maxSwapfee, _MIN_SWAP_FEE_PERCENTAGE, _MAX_SWAP_FEE_PERCENTAGE)
        );
        params.poolParams.maxTradeSizeRatio = uint64(bound(params.poolParams.maxTradeSizeRatio, 1e16, 30e16));
        params.numTokens = bound(params.numTokens, 2, 8);
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, 3e16, 1e18 / params.numTokens - 1)
        );

        _testSwapExactOut(params, swapParams);
    }
}
