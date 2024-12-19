// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

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
import { OracleWrapper } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";
import { MockUpdateWeightRunner } from "../../contracts/mock/MockUpdateWeightRunner.sol";
import { MockMomentumRule } from "../../contracts/mock/mockRules/MockMomentumRule.sol";
import { MockChainlinkOracle } from "../../contracts/mock/MockChainlinkOracles.sol";

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";

contract QuantAMMWeightedPoolFactoryTest is QuantAMMWeightedPoolContractsDeployer, BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum swap fee of 10%
    uint64 public constant MAX_SWAP_FEE_PERCENTAGE = 10e16;

    QuantAMMWeightedPoolFactory internal quantAMMWeightedPoolFactory;

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
        updateWeightRunner = new MockUpdateWeightRunner(owner, addr2, false);

        chainlinkOracle = _deployOracle(fixedValue, delay);

        updateWeightRunner.addOracle(OracleWrapper(chainlinkOracle));

        vm.stopPrank();

        quantAMMWeightedPoolFactory = deployQuantAMMWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        vm.label(address(quantAMMWeightedPoolFactory), "quantamm weighted pool factory");

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testPausedState() public view {
        uint32 pauseWindowDuration = quantAMMWeightedPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testEmptyOracleArrayFirst() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        params._poolSettings.oracles = new address[][](0);

        vm.expectRevert("NOPROVORC");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testEmptyOracleArrayMixed() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        params._poolSettings.oracles = new address[][](1);
        params._poolSettings.oracles[0] = new address[](0);

        vm.expectRevert("Empty oracles array");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testUnapprovedOracleArray() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        int216 fixedValue = 1000;
        uint delay = 3600;
        chainlinkOracle = _deployOracle(fixedValue, delay);
        params._poolSettings.oracles = new address[][](1);
        params._poolSettings.oracles[0] = new address[](1);
        params._poolSettings.oracles[0][0] = address(chainlinkOracle);

        vm.expectRevert("Not approved oracled used");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testInvalidRule() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.rule = IUpdateRule(address(0));
        vm.expectRevert("Invalid rule");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testInvalidRuleValidation() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.ruleParameters = new int256[][](0);
        vm.expectRevert("INVRLEPRM");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testEpsilonMaxInvalidAbove() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.epsilonMax = 1e18 + 1;
        vm.expectRevert("INV_EPMX");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testEpsilonMaxInvalidBelow() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.epsilonMax = 0e18;
        vm.expectRevert("INV_EPMX");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testEpsilonMaxValid() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.epsilonMax = 0.5e18;
        quantAMMWeightedPoolFactory.create(params);
    }

    function testLambdaInvalidEmpty() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.lambda = new uint64[](0);
        vm.expectRevert("Either scalar or vector");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testLambdaInvalidEmpty2D() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.lambda = new uint64[](1);
        vm.expectRevert("INVLAM");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testLambdaInvalidAbove() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.lambda = new uint64[](1);
        params._poolSettings.lambda[0] = 1e18 + 1;
        vm.expectRevert("INVLAM");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testLambdaInvalidBelow() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.lambda = new uint64[](1);
        params._poolSettings.lambda[0] = 0e18;
        vm.expectRevert("INVLAM");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testLambdaValid() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.lambda = new uint64[](1);
        params._poolSettings.lambda[0] = 0.5e18;
        quantAMMWeightedPoolFactory.create(params);
    }

    function testLambdaValid2D() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.lambda = new uint64[](2);
        params._poolSettings.lambda[0] = 0.5e18;
        params._poolSettings.lambda[1] = 0.5e18;
        quantAMMWeightedPoolFactory.create(params);
    }

    function testAbsoluteToleranceInvalidAbove() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.absoluteWeightGuardRail = 0.5e18 + 1;
        vm.expectRevert("INV_ABSWGT");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testAbsoluteToleranceInvalidBelow() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.absoluteWeightGuardRail = 0e18;
        vm.expectRevert("INV_ABSWGT");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testAbsoluteToleranceValid() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.absoluteWeightGuardRail = 0.2e18;
        quantAMMWeightedPoolFactory.create(params);
    }

    function testMaxTradeSizeInvalidAbove() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.maxTradeSizeRatio = 0.3e18 + 1;
        vm.expectRevert("INVMAXTRADE");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testMaxTradeSizeInvalidBelow() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.maxTradeSizeRatio = 0e18;
        vm.expectRevert("INVMAXTRADE");
        quantAMMWeightedPoolFactory.create(params);
    }

    function testMaxTradeSizeValid() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._poolSettings.maxTradeSizeRatio = 0.2e18;
        quantAMMWeightedPoolFactory.create(params);
    }

    function testInvalidWeightSum() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._initialWeights[0] = 0.6e18;
        vm.expectRevert(QuantAMMWeightedPool.NormalizedWeightInvariant.selector);
        quantAMMWeightedPoolFactory.create(params);
    }

    function testCreatePoolWithoutDonation() public {
        address quantAMMWeightedPool = _deployAndInitializeQuantAMMWeightedPool(false);

        // Try to donate but fails because pool does not support donations
        vm.prank(bob);
        vm.expectRevert(IVaultErrors.DoesNotSupportDonation.selector);
        router.donate(quantAMMWeightedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testCreatePoolWithDonation() public {
        uint256 amountToDonate = poolInitAmount;

        address quantAMMWeightedPool = _deployAndInitializeQuantAMMWeightedPool(true);

        HookTestLocals memory vars = _createHookTestLocals(quantAMMWeightedPool);

        // Donates to pool successfully
        vm.prank(bob);
        router.donate(quantAMMWeightedPool, [amountToDonate, amountToDonate].toMemoryArray(), false, bytes(""));

        _fillAfterHookTestLocals(vars, quantAMMWeightedPool);

        // Bob balances
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, amountToDonate, "Bob DAI balance is wrong");
        assertEq(vars.bob.usdcBefore - vars.bob.usdcAfter, amountToDonate, "Bob USDC balance is wrong");
        assertEq(vars.bob.bptAfter, vars.bob.bptBefore, "Bob BPT balance is wrong");

        // Pool balances
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], amountToDonate, "Pool DAI balance is wrong");
        assertEq(vars.poolAfter[usdcIdx] - vars.poolBefore[usdcIdx], amountToDonate, "Pool USDC balance is wrong");
        assertEq(vars.bptSupplyAfter, vars.bptSupplyBefore, "Pool BPT supply is wrong");

        // Vault Balances
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, amountToDonate, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcAfter - vars.vault.usdcBefore, amountToDonate, "Vault USDC balance is wrong");
    }

    function _createPoolParams() internal returns (QuantAMMWeightedPoolFactory.NewPoolParams memory retParams) {
        PoolRoleAccounts memory roleAccounts;
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        MockMomentumRule momentumRule = new MockMomentumRule(owner);

        uint32[] memory weights = new uint32[](2);
        weights[0] = uint32(uint256(0.5e18));
        weights[1] = uint32(uint256(0.5e18));

        int256[] memory initialWeights = new int256[](2);
        initialWeights[0] = 0.5e18;
        initialWeights[1] = 0.5e18;
        uint256[] memory initialWeightsUint = new uint256[](2);
        initialWeightsUint[0] = 0.5e18;
        initialWeightsUint[1] = 0.5e18;

        uint64[] memory lambdas = new uint64[](1);
        lambdas[0] = 0.2e18;
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        parameters[0][0] = 0.2e18;

        address[][] memory oracles = new address[][](1);
        oracles[0] = new address[](1);
        oracles[0][0] = address(chainlinkOracle);

        retParams = QuantAMMWeightedPoolFactory.NewPoolParams(
            "Pool With Donation",
            "PwD",
            vault.buildTokenConfig(tokens),
            initialWeightsUint,
            roleAccounts,
            MAX_SWAP_FEE_PERCENTAGE,
            address(0),
            true,
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32,
            initialWeights,
            IQuantAMMWeightedPool.PoolSettings(
                new IERC20[](2),
                IUpdateRule(momentumRule),
                oracles,
                60,
                lambdas,
                0.2e18,
                0.2e18,
                0.2e18,
                parameters,
                address(0)
            ),
            initialWeights,
            initialWeights,
            3600,
            0,
            new string[][](0)
        );
    }

    function _deployAndInitializeQuantAMMWeightedPool(bool supportsDonation) private returns (address) {
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.enableDonation = supportsDonation;
        params.name = supportsDonation ? "Pool With Donation" : "Pool Without Donation";
        params.symbol = supportsDonation ? "PwD" : "PwoD";

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        // Initialize pool.
        vm.prank(lp);
        router.initialize(
            quantAMMWeightedPool,
            tokens,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        return quantAMMWeightedPool;
    }

    struct WalletState {
        uint256 daiBefore;
        uint256 daiAfter;
        uint256 usdcBefore;
        uint256 usdcAfter;
        uint256 bptBefore;
        uint256 bptAfter;
    }

    struct HookTestLocals {
        WalletState bob;
        WalletState hook;
        WalletState vault;
        uint256[] poolBefore;
        uint256[] poolAfter;
        uint256 bptSupplyBefore;
        uint256 bptSupplyAfter;
    }

    function _createHookTestLocals(address pool) private view returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(bob);
        vars.bob.usdcBefore = usdc.balanceOf(bob);
        vars.bob.bptBefore = IERC20(pool).balanceOf(bob);
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
        vars.bptSupplyBefore = BalancerPoolToken(pool).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars, address pool) private view {
        vars.bob.daiAfter = dai.balanceOf(bob);
        vars.bob.usdcAfter = usdc.balanceOf(bob);
        vars.bob.bptAfter = IERC20(pool).balanceOf(bob);
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
        vars.bptSupplyAfter = BalancerPoolToken(pool).totalSupply();
    }
}
