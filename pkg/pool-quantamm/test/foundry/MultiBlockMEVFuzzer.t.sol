// SPDX-License-Identifier: MIT
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
import { QuantAMMMathGuard } from "../../contracts/rules/base/QuantammMathGuard.sol";

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";

contract MultiBlockMEVFuzzer is QuantAMMWeightedPoolContractsDeployer, BaseVaultTest, QuantAMMMathGuard {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // structs

    // @note this will be used to deposit and withdraw same token -> simplest case
    // @note advantage here is this is an apples to apples comparison and we don't need price of asset A against against B
    struct FuzzParamsSingleSameToken {
        PoolFuzzParams poolParams;
        uint256 tokenIndex; // valid values are 0-numTokens
        uint256 depositLiquidity; // liquidity deposited by LP to pool for asset with tokenIndex
    }

    // @note this will be used to deposit token A -> and withdraw token B
    struct FuzzParamsSingleDifferentToken {
        PoolFuzzParams poolParams;
        uint256 depositTokenIndex; // valid values are 0-numTokens
        uint256 withdrawTokenIndex; // valid values are 0-numTokens
        uint256 depositLiquidity; // liquidity deposited by LP to pool for asset with tokenIndex
    }

    //@note this is most generic case where Alice can deposit/withdraw pre/post weight update any number of tokens
    //@note in this case I will also assume that Alice can have existing BPT tokens (to simulate withdrawals pre-weight update)
    struct FuzzParamsMultiToken {
        PoolFuzzParams poolParams;
        LiquidityFuzzParams preWeightLiquidities;
        LiquidityFuzzParams postWeightLiquidities;
    }

    struct PoolFuzzParams {
        uint256 numTokens;
        uint64 epsilonMax;
        uint64 maxSwapfee;
        uint64 absoluteWeightGuardRail;
        uint64 maxTradeSizeRatio;
        uint256 delay; // window over which MEV opportunity exists -> can be from one to update interval
        BalanceFuzzParams intialBalance;
        WeightFuzzParams initialWeights;
        WeightFuzzParams targetWeights;
        uint256 existingBPTSupply;
    }

    struct WeightFuzzParams {
        int256 weight0;
        int256 weight1;
        int256 weight2;
        int256 weight3;
        int256 weight4;
        int256 weight5;
        int256 weight6;
        int256 weight7;
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
        int256 liquidity0;
        int256 liquidity1;
        int256 liquidity2;
        int256 liquidity3;
        int256 liquidity4;
        int256 liquidity5;
        int256 liquidity6;
        int256 liquidity7;
    }

    struct TestState {
        uint40 timestamp;
        address quantAMMWeightedPool;
        uint256 minThresholdProfit; // minimum profit that will make MEV viable
        uint256[] initialBalances;
        int256[] poolStartWeights;
        int256[] firstRandomWeights;
        int256[] secondRandomWeights;
    }

    // constants
    uint64 public constant _MAX_SWAP_FEE_PERCENTAGE = 10e16;
    uint16 private constant _UPDATE_INTERVAL = 60; // 60 seconds
    uint64 private constant _LAMBDA = 0.2e18; // 20% lambda
    int256 private constant _KAPPA = 0.2e18; // 20% kappa
    uint64 private constant _MAX_TRADE_SIZE_RATIO = 0.01e18; // 1% max trade size ratio
    uint256 _MIN_BALANCE = 1e18; // 1 token with 18 decimals
    uint256 _MAX_BALANCE = 1e24;

    // state
    QuantAMMWeightedPoolFactory internal quantAMMWeightedPoolFactory;

    function setUp() public override {
        super.setUp();

        (address ownerLocal, address addr1Local, address addr2Local) = (vm.addr(1), vm.addr(2), vm.addr(3));
        owner = ownerLocal;
        addr1 = addr1Local;
        addr2 = addr2Local;

        // Deploy UpdateWeightRunner contract
        vm.startPrank(owner);
        updateWeightRunner = new MockUpdateWeightRunner(owner, addr2, false); //@note owner = vault admin, addr2 = eth oracle

        int216 fixedValue = 1000;
        uint delay = 3600;
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
        tokens_ = _sortTokens(tokens_);
        return tokens_;
    }

    function _sortTokens(IERC20[] memory inputTokens) internal pure returns (IERC20[] memory) {
        for (uint256 i = 0; i < inputTokens.length - 1; ++i) {
            for (uint256 j = 0; j < inputTokens.length - i - 1; ++j) {
                if (inputTokens[j] > inputTokens[j + 1]) {
                    // Swap if they're out of order.
                    (inputTokens[j], inputTokens[j + 1]) = (inputTokens[j + 1], inputTokens[j]);
                }
            }
        }

        return inputTokens;
    }

    function _getInitialBalances(
        uint256 numTokens,
        BalanceFuzzParams memory balanceParams
    ) internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](numTokens);

        balances[0] = bound(balanceParams.balance0, _MIN_BALANCE, _MAX_BALANCE);
        balances[1] = bound(balanceParams.balance1, _MIN_BALANCE, _MAX_BALANCE);

        if (numTokens > 2) {
            balances[2] = bound(balanceParams.balance2, _MIN_BALANCE, _MAX_BALANCE);
        }
        if (numTokens > 3) {
            balances[3] = bound(balanceParams.balance3, _MIN_BALANCE, _MAX_BALANCE);
        }

        if (numTokens > 4) {
            balances[4] = bound(balanceParams.balance4, _MIN_BALANCE, _MAX_BALANCE);
        }

        if (numTokens > 5) {
            balances[5] = bound(balanceParams.balance5, _MIN_BALANCE, _MAX_BALANCE);
        }

        if (numTokens > 6) {
            balances[6] = bound(balanceParams.balance6, _MIN_BALANCE, _MAX_BALANCE);
        }

        if (numTokens > 7) {
            balances[7] = bound(balanceParams.balance7, _MIN_BALANCE, _MAX_BALANCE);
        }

        return balances;
    }

    function _createPoolParams(
        PoolFuzzParams memory params
    ) internal returns (QuantAMMWeightedPoolFactory.NewPoolParams memory) {
        // Create base params first
        QuantAMMWeightedPoolFactory.NewPoolParams memory baseParams = _createBaseParams(
            params.numTokens,
            params.maxSwapfee
        );

        // Update with pool settings
        baseParams._poolSettings = _createPoolSettings(params);

        return baseParams;
    }

    function _createBaseParams(
        uint256 numTokens,
        uint64 maxSwapFee
    ) internal returns (QuantAMMWeightedPoolFactory.NewPoolParams memory) {
        PoolRoleAccounts memory roleAccounts;
        tokens = _getTokens(numTokens);

        (uint256[] memory initialWeightsUint, int256[] memory initialWeights) = _createInitialWeights(numTokens);

        return
            QuantAMMWeightedPoolFactory.NewPoolParams({
                name: "PoolZ",
                symbol: "PwZ",
                tokens: vault.buildTokenConfig(tokens),
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
        PoolFuzzParams memory params
    ) internal returns (IQuantAMMWeightedPool.PoolSettings memory) {
        MockMomentumRule momentumRule = new MockMomentumRule(owner);

        int256[][] memory ruleParams = new int256[][](1);
        ruleParams[0] = new int256[](1);
        ruleParams[0][0] = _KAPPA;

        uint64[] memory lambdas = new uint64[](1);
        lambdas[0] = _LAMBDA;

        address[][] memory oracles = new address[][](1);
        oracles[0] = new address[](1);
        oracles[0][0] = address(chainlinkOracle);

        return
            IQuantAMMWeightedPool.PoolSettings({
                assets: new IERC20[](params.numTokens),
                rule: IUpdateRule(address(momentumRule)),
                oracles: oracles,
                updateInterval: _UPDATE_INTERVAL,
                lambda: lambdas,
                epsilonMax: params.epsilonMax,
                absoluteWeightGuardRail: params.absoluteWeightGuardRail,
                maxTradeSizeRatio: _MAX_TRADE_SIZE_RATIO,
                ruleParameters: ruleParams,
                poolManager: address(0)
            });
    }

    // @note this function only checks min/max weight range
    // this function deliberately excludes epsilonMax condition -> I am using this to set first set of random weights
    // not checking epsilonMax because the first set of weigts can be N number of updateIntervals from the pool creation
    function _boundWeights(
        WeightFuzzParams memory weights,
        uint256 numTokens,
        uint64 absWeightGuardRail
    ) internal pure returns (int256[] memory) {
        int256[] memory result = new int256[](numTokens);
        int256 G = int256(uint256(absWeightGuardRail));
        int256 remainingWeight = 1e18; // Start with total weight of 1

        // For each token except the last one
        for (uint i = 0; i < numTokens - 1; i++) {
            // Min weight is always G
            int256 minWeight = G;

            // Max weight is what's remaining minus minimum weights needed for remaining tokens
            int256 maxWeight = remainingWeight - (G * int256(numTokens - i - 1));

            // Get weight value based on index
            int256 weight = i == 0 ? weights.weight0 : i == 1 ? weights.weight1 : i == 2 ? weights.weight2 : i == 3
                ? weights.weight3
                : i == 4
                ? weights.weight4
                : i == 5
                ? weights.weight5
                : i == 6
                ? weights.weight6
                : weights.weight7;

            // Bound this weight between min and max
            result[i] = bound(weight, minWeight, maxWeight);

            // Update remaining weight for next token
            remainingWeight -= result[i];
        }

        // Last token gets exactly what's left
        result[numTokens - 1] = remainingWeight;

        return result;
    }

    // @note this is used for setting second set of weights
    // since this comes at the end of update interval AFTER first set of weights
    // in this function I'm additionally checking for epsilonMax
    function _boundSecondWeights(
        int256[] memory firstWeights,
        WeightFuzzParams memory targetWeights,
        uint256 numTokens,
        uint64 absWeightGuardRail,
        uint64 epsilonMax
    ) internal pure returns (int256[] memory) {
        // First get weights within guard rail bounds
        int256[] memory boundedWeights = _boundWeights(targetWeights, numTokens, absWeightGuardRail);

        // checks epsilon Max
        boundedWeights = _normalizeWeightUpdates(firstWeights, boundedWeights, int256(uint256(epsilonMax)));

        return boundedWeights;
    }

    function _addInitialLiquidity(address poolAddress, uint256[] memory amounts) internal returns (uint256) {
        IERC20[] memory poolTokens = IQuantAMMWeightedPool(poolAddress).getQuantAMMWeightedPoolImmutableData().tokens;

        // add initial liquidity
        return router.initialize(poolAddress, poolTokens, amounts, 0, false, "");
    }

    function _dealAndApprove(address user, address ammPool, uint256[] memory amounts) internal {
        // Get the pool tokens
        IERC20[] memory poolTokens = IQuantAMMWeightedPool(ammPool).getQuantAMMWeightedPoolImmutableData().tokens;

        for (uint i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) continue;
            deal(address(poolTokens[i]), user, amounts[i]);
        }

        // Setup approvals
        vm.startPrank(user);
        for (uint i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) continue;
            poolTokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(poolTokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(poolTokens[i]), address(vault), type(uint160).max, type(uint48).max);

            assertEq(poolTokens[i].allowance(user, address(permit2)), type(uint256).max, "Token approval failed");
        }

        // Additionally approve BPT token for router (for withdrawals later)
        IERC20(ammPool).approve(address(router), type(uint256).max);
        IERC20(ammPool).approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Final balance check
        for (uint i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) continue;
            assertEq(poolTokens[i].balanceOf(user), amounts[i], "Token dealing failed");
        }
    }

    function _addLiquidityUnbalancedSingleToken(
        address poolAddress,
        uint256 tokenIndex,
        uint256 amount
    ) internal returns (uint256) {
        uint256[] memory amounts = new uint256[](
            IQuantAMMWeightedPool(poolAddress).getQuantAMMWeightedPoolImmutableData().tokens.length
        );
        amounts[tokenIndex] = amount;
        return router.addLiquidityUnbalanced(poolAddress, amounts, 0, false, "");
    }

    function _removeLiquidityUnbalancedSingleToken(
        address poolAddress,
        uint256 tokenIndex,
        uint256 bptRedeemed
    ) internal returns (uint256) {
        IERC20[] memory poolTokens = IQuantAMMWeightedPool(poolAddress).getQuantAMMWeightedPoolImmutableData().tokens;
        uint256[] memory minAmountsOut = new uint256[](poolTokens.length);

        for (uint i = 0; i < minAmountsOut.length; i++) {
            minAmountsOut[i] = 0;
        }

        minAmountsOut[tokenIndex] = 1; //@note settin this to 0 is causing an error of AllZeroInputs

        uint256 amountsOut = router.removeLiquiditySingleTokenExactIn(
            poolAddress,
            bptRedeemed,
            poolTokens[tokenIndex],
            minAmountsOut[tokenIndex] /* min amount out*/,
            false,
            ""
        );
        return amountsOut;
    }

    function _checkAllowances(address user, address ammPool) internal view {
        IERC20 bpt = IERC20(ammPool);
        console.log("BPT balance of user:", bpt.balanceOf(user));
        console.log("BPT allowance for Router:", bpt.allowance(user, address(router)));
        console.log("BPT allowance for Vault:", bpt.allowance(user, address(vault)));
        console.log("BPT allowance for 0xD16d...70:", bpt.allowance(user, 0xD16d567549A2a2a2005aEACf7fB193851603dd70));
    }

    function _getCurrentWeights(address poolAddress) internal view returns (int256[] memory) {
        uint256[] memory normalizedWeights = IQuantAMMWeightedPool(poolAddress).getNormalizedWeights();

        int256[] memory weightsInt = new int256[](normalizedWeights.length);
        for (uint i = 0; i < normalizedWeights.length; i++) {
            weightsInt[i] = int256(normalizedWeights[i]);
        }
        return weightsInt;
    }

    function _validateAndBoundParams(FuzzParamsSingleSameToken memory params) private pure {
        // fuzz param constraints
        params.poolParams.numTokens = bound(params.poolParams.numTokens, 2, 8);
        params.tokenIndex = bound(params.tokenIndex, 0, params.poolParams.numTokens - 1);

        // Bound parameters to valid ranges
        params.poolParams.delay = bound(params.poolParams.delay, 0, _UPDATE_INTERVAL);
        params.poolParams.maxSwapfee = uint64(bound(params.poolParams.maxSwapfee, 1e16, _MAX_SWAP_FEE_PERCENTAGE)); // min of 1% and max of 10%
        params.poolParams.epsilonMax = uint64(bound(params.poolParams.epsilonMax, 0.001e18, 0.01e18)); // 0.1% to 25% @audit epsilon
        params.poolParams.absoluteWeightGuardRail = uint64(
            bound(params.poolParams.absoluteWeightGuardRail, 0.03e18, 1e18 / params.poolParams.numTokens - 1)
        ); // 1% to 100%/numTokens
        params.poolParams.maxTradeSizeRatio = uint64(bound(params.poolParams.maxTradeSizeRatio, 0.01e18, 0.3e18)); // 1% to 30%
    }

    function _setupPool(
        FuzzParamsSingleSameToken memory params,
        uint256[] memory initialBalances
    ) private returns (address, uint256) {
        QuantAMMWeightedPoolFactory.NewPoolParams memory newParams = _createPoolParams(params.poolParams);
        (address ammPool, ) = quantAMMWeightedPoolFactory.create(newParams);

        // Ensure LP has enough tokens and that router has approval to transfer those tokens
        _dealAndApprove(lp, ammPool, initialBalances);

        vm.startPrank(lp);
        uint256 bptAmountOut = _addInitialLiquidity(ammPool, initialBalances);
        vm.stopPrank();

        return (ammPool, bptAmountOut);
    }

    function _verifyInitialSetup(
        address ammPool,
        uint256[] memory initialBalances,
        uint256 bptAmountReceivedOnDeposit
    ) private view {
        uint256 initialSupply = IERC20(ammPool).totalSupply();
        assertEq(bptAmountReceivedOnDeposit + 1e6, initialSupply, "BPT amount out should be equal to initial supply");
        //@note _POOL_MINIMUM_TOTAL_SUPPLY is 1e6

        uint256[] memory poolBalances = vault.getCurrentLiveBalances(ammPool);
        for (uint i = 0; i < poolBalances.length; i++) {
            assertEq(poolBalances[i], initialBalances[i], "Pool balance mismatch for token");
        }
    }

    function _handleFirstWeightChange(
        FuzzParamsSingleSameToken memory params,
        address ammPool,
        uint40
    ) private returns (int256[] memory poolStartWeights, int256[] memory firstRandomWeights) {
        poolStartWeights = _getCurrentWeights(ammPool);

        firstRandomWeights = _boundWeights(
            params.poolParams.initialWeights,
            params.poolParams.numTokens,
            params.poolParams.absoluteWeightGuardRail
        );

        updateWeightRunner.calculateMultiplierAndSetWeights(
            poolStartWeights,
            firstRandomWeights,
            _UPDATE_INTERVAL,
            params.poolParams.absoluteWeightGuardRail,
            ammPool
        );

        return (poolStartWeights, firstRandomWeights);
    }

    function _handleAliceDeposit(
        FuzzParamsSingleSameToken memory params,
        address ammPool,
        uint40
    ) private returns (uint256 bptReceived, uint256 boundedDeposit) {
        // Calculate max safe deposit based on current pool state
        uint256[] memory currentBalances = vault.getCurrentLiveBalances(ammPool);

        // Get max invariant ratio from pool
        uint256 maxInvariantRatio = QuantAMMWeightedPool(ammPool).getMaximumInvariantRatio();

        // Calculate max safe deposit amount that won't exceed maxInvariantRatio
        // For single token add, max safe amount is roughly:
        // currentBalance * (maxInvariantRatio - 1)
        uint256 maxSafeDeposit = currentBalances[params.tokenIndex].mulDown(maxInvariantRatio - FixedPoint.ONE);

        // Bound deposit amount to be within safe limits
        boundedDeposit = bound(
            params.depositLiquidity,
            1e18, // Min meaningful deposit
            maxSafeDeposit
        );

        uint256[] memory aliceDeposits = new uint256[](params.poolParams.numTokens);
        aliceDeposits[params.tokenIndex] = boundedDeposit;
        _dealAndApprove(alice, ammPool, aliceDeposits);

        vm.startPrank(alice);
        bptReceived = _addLiquidityUnbalancedSingleToken(ammPool, params.tokenIndex, boundedDeposit);
        vm.stopPrank();

        return (bptReceived, boundedDeposit);
    }

    function _verifyAliceDeposit(address ammPool, uint256 tokenIndex, uint256) private view {
        IERC20 token = IQuantAMMWeightedPool(ammPool).getQuantAMMWeightedPoolImmutableData().tokens[tokenIndex];
        assertEq(token.balanceOf(alice), 0, "Alice's token balance should be 0 after deposit");

        IERC20 bpt = IERC20(ammPool);
        assertGt(bpt.balanceOf(alice), 0, "Alice's BPT balance should be non-zero after deposit");
    }

    function _handleSecondWeightChange(
        FuzzParamsSingleSameToken memory params,
        address ammPool,
        int256[] memory firstRandomWeights
    ) private returns (int256[] memory secondRandomWeights) {
        secondRandomWeights = _boundSecondWeights(
            firstRandomWeights,
            params.poolParams.targetWeights,
            params.poolParams.numTokens,
            params.poolParams.absoluteWeightGuardRail,
            params.poolParams.epsilonMax
        );

        updateWeightRunner.calculateMultiplierAndSetWeights(
            firstRandomWeights,
            secondRandomWeights,
            _UPDATE_INTERVAL,
            params.poolParams.absoluteWeightGuardRail,
            ammPool
        );

        logWeightChange(firstRandomWeights, secondRandomWeights);

        return secondRandomWeights;
    }

    function logWeightChange(int256[] memory firstRandomWeights, int256[] memory secondRandomWeights) private view {
        for (uint i; i < firstRandomWeights.length; i++) {
            console.logString(
                string.concat(
                    vm.toString(i),
                    " weight before: ",
                    vm.toString(firstRandomWeights[i]),
                    " weight after: ",
                    vm.toString(secondRandomWeights[i])
                )
            );
        }
    }

    function _verifyInterpolationTimes(address ammPool, uint40 timestamp) private view {
        IQuantAMMWeightedPool.QuantAMMWeightedPoolDynamicData memory poolData = IQuantAMMWeightedPool(ammPool)
            .getQuantAMMWeightedPoolDynamicData();

        assertEq(poolData.lastUpdateIntervalTime, timestamp, "Last update interval time mismatch");
    }

    function _handleAliceWithdrawal(
        FuzzParamsSingleSameToken memory params,
        address ammPool,
        uint256 bptReceived
    ) private returns (uint256) {
        console.log("---After Approvals---");
        _checkAllowances(alice, ammPool);

        // Get current pool state
        uint256[] memory currentBalances = vault.getCurrentLiveBalances(ammPool);
        uint256 currentSupply = IERC20(ammPool).totalSupply();

        // Get min invariant ratio from pool
        uint256 minInvariantRatio = QuantAMMWeightedPool(ammPool).getMinimumInvariantRatio();

        //@note For single token remove with exact BPT in, we need to ensure:
        // newBalance/currentBalance >= minInvariantRatio for the withdrawn token
        // just like the fix I did when adding liquidity, I'm doing something similar here

        // This means: currentBalance - amountOut >= currentBalance * minInvariantRatio
        // => amountOut <= currentBalance * (1 - minInvariantRatio)

        // Calculate max safe withdrawal that maintains min invariant ratio
        uint256 maxSafeWithdrawal = currentBalances[params.tokenIndex].mulDown(
            FixedPoint.ONE - (minInvariantRatio + 100)
        ); // @note 100 added to prevent rounding errors

        // Calculate what portion of total supply our BPT represents
        uint256 proportionalWithdrawRatio = bptReceived.divDown(currentSupply);

        // Approximate expected withdrawal amount based on proportional share
        uint256 expectedWithdrawalAmount = currentBalances[params.tokenIndex].mulDown(proportionalWithdrawRatio);

        // Bound BPT amount to withdraw to be within safe limits
        // Fuzz adds a floor to BPT redeemable -> as anything above cannot be done for this token -> another token needs to be withdrawn
        uint256 boundedBptAmount;
        if (expectedWithdrawalAmount > maxSafeWithdrawal) {
            // Scale down BPT amount proportionally
            boundedBptAmount = bptReceived.mulDown(maxSafeWithdrawal).divDown(expectedWithdrawalAmount);
        } else {
            boundedBptAmount = bptReceived;
        }
        vm.startPrank(alice);
        uint256 amountOut = _removeLiquidityUnbalancedSingleToken(ammPool, params.tokenIndex, boundedBptAmount);
        vm.stopPrank();
        return amountOut;
    }

    function _verifyAliceWithdrawal(
        address ammPool,
        FuzzParamsSingleSameToken memory params,
        uint256 amountOut
    ) private view {
        IERC20 token = IQuantAMMWeightedPool(ammPool).getQuantAMMWeightedPoolImmutableData().tokens[params.tokenIndex];
        assertEq(
            token.balanceOf(alice),
            amountOut,
            "Alice's token balance should be equal to amount out after withdrawal"
        );
    }

    function _verifyWeightMatch(int256[] memory expectedWeights, int256[] memory actualWeights) private pure {
        for (uint i = 0; i < expectedWeights.length; i++) {
            assertEq(expectedWeights[i], actualWeights[i], "Weight mismatch");
        }
    }

    function _logFuzzParams(
        FuzzParamsSingleSameToken memory params,
        int256 profit,
        uint256 minThresholdProfit
    ) private view {
        console.log("**********Fuzz Params************* ");
        console.logString(string.concat("Num Tokens: ", vm.toString(params.poolParams.numTokens)));
        console.logString(
            string.concat(
                "Absolute Weight Guard Rail:",
                vm.toString(params.poolParams.absoluteWeightGuardRail / 1e16),
                "%"
            )
        );
        console.logString(string.concat("Epsilon Max:", vm.toString(params.poolParams.epsilonMax / 1e16), "%"));
        console.logString(string.concat("Max Swap Fee:", vm.toString(params.poolParams.maxSwapfee / 1e16), "%"));
        console.logString(string.concat("Delay:", vm.toString(params.poolParams.delay)));

        console.logString(string.concat("Token Index:", vm.toString(params.tokenIndex)));
        console.logString(string.concat("Profit threshold:", vm.toString(minThresholdProfit / 1e18)));
        console.logString(string.concat("Profit:", vm.toString(profit / 1e18)));
        console.log("----------------------------------");
    }

    function testSingleTokenSameAssetMEV_Fuzz(FuzzParamsSingleSameToken memory params) public {
        TestState memory poolState;
        poolState.timestamp = uint40(block.timestamp);

        // 1. Validate and bound parameters
        _validateAndBoundParams(params);
        console.log("Step 1: Validate And Bound Fuzz Params - COMPLETED***");

        // 2. Get initial balances array
        poolState.initialBalances = _getInitialBalances(params.poolParams.numTokens, params.poolParams.intialBalance);
        console.log("Step 2: Initial balances calculation - COMPLETED***");

        // 3. Create pool with initial weights, and fund pool with initial balances
        uint256 bptReceivedOnDeposit;
        (poolState.quantAMMWeightedPool, bptReceivedOnDeposit) = _setupPool(params, poolState.initialBalances);
        console.log("Step 3: Create and fund pool with initial balances - COMPLETED***");

        // 4. Verify the pool indeed has the balances and bpt supply > 0
        _verifyInitialSetup(poolState.quantAMMWeightedPool, poolState.initialBalances, bptReceivedOnDeposit);
        console.log("Step 4: Pool balance verifications - COMPLETED***");

        //5. Now move forward in time by UPDATE_INTERVAL to update weights
        vm.warp(poolState.timestamp + _UPDATE_INTERVAL);
        console.log("Step 5: Time jump to first update - COMPLETED***");

        // 6. Set weights to the first set of random weights
        //@note that I'm deliberately not constraining weights to the epsilonMax condition for the first weight change
        // I'm assuming 1 update interval time jump from pool initialization for the test -> but in reality it could be any number of update intervals
        // @note effectively our test is starting from here -> had to do this because I didn't want to start off with dummy initial weights
        (poolState.poolStartWeights, poolState.firstRandomWeights) = _handleFirstWeightChange(
            params,
            poolState.quantAMMWeightedPool,
            poolState.timestamp
        );
        console.log("Step 6: Weights update first time - COMPLETED***");

        // 7. verify that setWeights is called
        _verifyInterpolationTimes(poolState.quantAMMWeightedPool, poolState.timestamp + _UPDATE_INTERVAL); //checks setWeights updates lastUpdateTime and lastInterpolationTimePossible
        console.log("Step 7: Weight update verification - COMPLETED***");

        // 8. Move forward in time again by update interval
        vm.warp(poolState.timestamp + 2 * _UPDATE_INTERVAL); // jump ahead by 2* update interval
        console.log("Step 8: Time jump to second update - COMPLETED***");

        //9. Right before weights are updated, Alice deposits into the pool
        (uint256 bptReceived, uint256 boundedDeposit) = _handleAliceDeposit(
            params,
            poolState.quantAMMWeightedPool,
            poolState.timestamp
        );
        console.log("Step 9: Alice deposit - COMPLETED***");

        //10. Verify Alice Deposit
        _verifyAliceDeposit(poolState.quantAMMWeightedPool, params.tokenIndex, bptReceived);
        console.log("Step 10: Alice deposit verification - COMPLETED***");

        //11. Set weights to the second set of random weights

        poolState.secondRandomWeights = _handleSecondWeightChange(
            params,
            poolState.quantAMMWeightedPool,
            poolState.firstRandomWeights
        );
        console.log("Step 11: Second weight update - COMPLETED***");

        //12. verify set weights are updated
        _verifyInterpolationTimes(poolState.quantAMMWeightedPool, poolState.timestamp + 2 * _UPDATE_INTERVAL);
        console.log("Step 12.1: Verify second weight update - COMPLETED***", block.timestamp);

        // 13: Move a few blocks ahead
        //@note I am fuzzing few blocks by using delay as proxy -> delay can be from 0 seconds to update interval
        //@note so multi block sandwiching could be instantaneous or span the whole update interval
        vm.warp(poolState.timestamp + 2 * _UPDATE_INTERVAL + params.poolParams.delay);
        console.log("Step 13: Time jump to a fuzzed delay - COMPLETED***", block.timestamp);

        //14. Alice withdraws
        uint256 aliceBalanceBefore = IQuantAMMWeightedPool(poolState.quantAMMWeightedPool)
            .getQuantAMMWeightedPoolImmutableData()
            .tokens[params.tokenIndex]
            .balanceOf(alice);
        uint256 amountOut = _handleAliceWithdrawal(params, poolState.quantAMMWeightedPool, bptReceived);
        console.log("Step 14: Alice withdrawal - COMPLETED***");

        //15. Verify Alice Withdrawal
        _verifyAliceWithdrawal(poolState.quantAMMWeightedPool, params, aliceBalanceBefore + amountOut);
        console.log("Step 15: Verify Alice withdrawal - COMPLETED***");

        //16. Alice's profit from the trade should be less than a min threshold profit -> anything above will incentvize MEV searchers/arbitragers
        // logging any such instances
        console.log("amount out", amountOut);
        console.log("boundedDeposit", boundedDeposit);

        poolState.minThresholdProfit = (boundedDeposit * 10001) / 10000;

        int256 profitLoss = int256(amountOut) - int256(boundedDeposit);
        if (profitLoss > int256(poolState.minThresholdProfit)) {
            _logFuzzParams(params, profitLoss, poolState.minThresholdProfit);
        }

        assertLe(profitLoss, int256(poolState.minThresholdProfit), "Profit should be less than min threshold profit");
    }

    function testSingleTokenDifferentAssetMEV_Fuzz(FuzzParamsSingleDifferentToken memory params) public {
        // TBD
    }

    function testMultiTokenMEV_Fuzz(FuzzParamsMultiToken memory params) public {
        // TBD
    }
}
