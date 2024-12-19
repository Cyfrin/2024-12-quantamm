// SPDX-License-Identifier: GPL-3.0-or-later

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

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";

contract QuantAMMWeightedPool8TokenTest is QuantAMMWeightedPoolContractsDeployer, BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

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
    }

    function testGetNormalizedWeightsInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._initialWeights[6] = 0.1e18;
        params._initialWeights[7] = 0.15e18;

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.125e18);
        assertEq(weights[1], 0.125e18);
        assertEq(weights[2], 0.125e18);
        assertEq(weights[3], 0.125e18);
        assertEq(weights[4], 0.125e18);
        assertEq(weights[5], 0.125e18);
        assertEq(weights[6], 0.1e18);
        assertEq(weights[7], 0.15e18);
    }

    function testSetWeightInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        int256[] memory newWeights = _getDefaultWeightAndMultiplier();
        newWeights[0] = 0.1e18;
        newWeights[1] = 0.15e18;

        vm.prank(address(updateWeightRunner));
        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.1e18);
        assertEq(weights[1], 0.15e18);
        assertEq(weights[2], 0.125e18);
        assertEq(weights[3], 0.125e18);
        assertEq(weights[4], 0.125e18);
        assertEq(weights[5], 0.125e18);
        assertEq(weights[6], 0.125e18);
        assertEq(weights[7], 0.125e18);
    }

    function testSetWeightNBlocksAfter() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));

        int256[] memory newWeights = _getDefaultWeightAndMultiplier();
        newWeights[0] = 0.1e18;
        newWeights[1] = 0.15e18;

        newWeights[8] = 0.001e18;
        newWeights[9] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 2);

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.1e18 + 0.002e18);
        assertEq(weights[1], 0.15e18 + 0.002e18);
    }

    function testSetWeightAfterLimit() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = _getDefaultWeightAndMultiplier();
        newWeights[0] = 0.1e18;
        newWeights[1] = 0.15e18;

        newWeights[8] = 0.001e18;
        newWeights[9] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 7);

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.1e18 + 0.005e18);
        assertEq(weights[1], 0.15e18 + 0.005e18);
    }

    struct testParam {
        uint index;
        int256 weight;
        int256 multiplier;
    }

    function _computeBalanceInternal(
        testParam memory firstWeight,
        testParam memory secondWeight,
        uint delay,
        uint256 expected
    ) internal {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = _getDefaultWeightAndMultiplier();
        newWeights[firstWeight.index] = firstWeight.weight;
        newWeights[secondWeight.index] = secondWeight.weight;

        newWeights[firstWeight.index + 8] = firstWeight.multiplier;
        newWeights[secondWeight.index + 8] = secondWeight.multiplier;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        if (delay > 0) {
            vm.warp(block.timestamp + delay);
        }

        uint256[] memory balances = _getDefaultBalances();

        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).computeBalance(
            balances,
            firstWeight.index,
            uint256(1.2e18)
        );

        assertEq(newBalance, expected);
    }

    function testComputeBalanceInitialToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 0, 6191.736422400061905000e18);
    }

    function testComputeBalanceNBlocksAfterToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 2, 5974.295859424989510000e18);
    }

    function testComputeBalanceAfterLimitToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 7, 5676.845898799479439000e18);
    }

    function testComputeBalanceInitialToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 0, 6191.736422400061905000e18);
    }

    function testComputeBalanceNBlocksAfterToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 2, 5974.295859424989510000e18);
    }

    function testComputeBalanceAfterLimitToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 7, 5676.845898799479439000e18);
    }

    function testComputeBalanceInitialToken7Token5() public {
        testParam memory firstWeight = testParam(5, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(7, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 0, 46438.023168000464287500e18);
    }

    function testComputeBalanceNBlocksAfterToken7Token5() public {
        testParam memory firstWeight = testParam(5, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(7, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 2, 44807.218945687421325000e18);
    }

    function testComputeBalanceAfterLimitToken7Token5() public {
        testParam memory firstWeight = testParam(5, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(7, 0.15e18, 0.001e18);
        _computeBalanceInternal(firstWeight, secondWeight, 7, 42576.344240996095792500e18);
    }

    function _onSwapOutGivenInInternal(
        testParam memory firstWeight,
        testParam memory secondWeight,
        uint delay,
        uint256 expected
    ) internal {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = _getDefaultWeightAndMultiplier();
        newWeights[firstWeight.index] = firstWeight.weight;
        newWeights[secondWeight.index] = secondWeight.weight;

        newWeights[firstWeight.index + 8] = firstWeight.multiplier;
        newWeights[secondWeight.index + 8] = secondWeight.multiplier;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        if (delay > 0) {
            vm.warp(block.timestamp + delay);
        }

        uint256[] memory balances = _getDefaultBalances();

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 1e18,
            balancesScaled18: balances,
            indexIn: firstWeight.index,
            indexOut: secondWeight.index,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, expected);
    }

    function testGetNormalizedWeightOnSwapOutGivenInInitialToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 0, 1.332223208952048000e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInNBlocksAfterToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 2, 1.340984896364186000e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInAfterLimitToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 7, 1.353703406520588000e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInInitialToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 0, 4.995837033570180000e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInNBlocksAfterToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 2, 5.028693361365697500e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInAfterLimitToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 7, 5.076387774452205000e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInInitialToken7Token5() public {
        testParam memory firstWeight = testParam(7, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 0, 0.999833362882522500e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInNBlocksAfterToken7Token5() public {
        testParam memory firstWeight = testParam(7, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 2, 1.006410772600252500e18);
    }

    function testGetNormalizedWeightOnSwapOutGivenInAfterLimitToken7Token5() public {
        testParam memory firstWeight = testParam(7, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 7, 1.015958615150850000e18);
    }

    // cross swap not working correctly
    function testGetNormalizedWeightOnSwapOutGivenInitialToken7Token0() public {
        testParam memory firstWeight = testParam(7, 0.1e18, 0.001e18); // indexIn > 4
        testParam memory secondWeight = testParam(3, 0.15e18, 0.001e18); // indexOut < 4
        // will revert on underflow
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 0, 0.046658890267851050e18);
    }

    // index >= 4 not working correctly
    function testGetNormalizedWeightOnSwapOutGivenInInitialToken0Token4() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(4, 0.15e18, 0.001e18);
        // fails with panic: array out-of-bounds access
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 0, 0.499583703357018000e18);
    }

    // index >= 4 not working correctly
    function testGetNormalizedWeightOnSwapOutGivenInInitialToken4Token0() public {
        testParam memory firstWeight = testParam(4, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(0, 0.15e18, 0.001e18);
        // fails with panic: array out-of-bounds access
        _onSwapOutGivenInInternal(firstWeight, secondWeight, 0, 0.887902403682279000e18);
    }

    function _onSwapInGivenOutInternal(
        testParam memory firstWeight,
        testParam memory secondWeight,
        uint delay,
        uint256 expected
    ) internal {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = _getDefaultWeightAndMultiplier();
        newWeights[firstWeight.index] = firstWeight.weight;
        newWeights[secondWeight.index] = secondWeight.weight;

        newWeights[firstWeight.index + 8] = firstWeight.multiplier;
        newWeights[secondWeight.index + 8] = secondWeight.multiplier;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        if (delay > 0) {
            vm.warp(block.timestamp + delay);
        }

        uint256[] memory balances = _getDefaultBalances();

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: 1e18,
            balancesScaled18: balances,
            indexIn: firstWeight.index,
            indexOut: secondWeight.index,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, expected);
    }

    function testGetNormalizedWeightOnSwapInGivenOutInitialToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 0, 0.750469023601402000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutNBlocksAfterToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 2, 0.745562169258142000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutAfterLimitToken0Token1() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(1, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 7, 0.738552419074452000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutInitialToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 0, 0.200033338529300000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutNBlocksAfterToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 2, 0.198725801188834000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutAfterLimitToken0Token5() public {
        testParam memory firstWeight = testParam(0, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(5, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 7, 0.196857893667587000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutInitialToken5Token7() public {
        testParam memory firstWeight = testParam(5, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(7, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 0, 2.250562631354580000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutNBlocksAfterToken5Token7() public {
        testParam memory firstWeight = testParam(5, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(7, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 2, 2.235850879332765000e18);
    }

    function testGetNormalizedWeightOnSwapInGivenOutAfterLimitToken5Token7() public {
        testParam memory firstWeight = testParam(5, 0.1e18, 0.001e18);
        testParam memory secondWeight = testParam(7, 0.15e18, 0.001e18);
        _onSwapInGivenOutInternal(firstWeight, secondWeight, 7, 2.214834140775105000e18);
    }

    function _getDefaultBalances() internal pure returns (uint256[] memory balances) {
        balances = new uint256[](8);
        balances[0] = 1000e18;
        balances[1] = 2000e18;
        balances[2] = 500e18;
        balances[3] = 350e18;
        balances[4] = 750e18;
        balances[5] = 7500e18;
        balances[6] = 8000e18;
        balances[7] = 5000e18;
    }

    function _getDefaultWeightAndMultiplier() internal pure returns (int256[] memory weights) {
        weights = new int256[](16);
        weights[0] = 0.125e18;
        weights[1] = 0.125e18;
        weights[2] = 0.125e18;
        weights[3] = 0.125e18;
        weights[4] = 0.125e18;
        weights[5] = 0.125e18;
        weights[6] = 0.125e18;
        weights[7] = 0.125e18;
        weights[8] = 0.025e18;
        weights[9] = 0.025e18;
        weights[10] = 0.025e18;
        weights[11] = 0.025e18;
        weights[12] = 0.025e18;
        weights[13] = 0.025e18;
        weights[14] = 0.025e18;
        weights[15] = 0.025e18;
    }

    function _createPoolParams() internal returns (QuantAMMWeightedPoolFactory.NewPoolParams memory retParams) {
        PoolRoleAccounts memory roleAccounts;
        IERC20[] memory tokens = [
            address(dai),
            address(usdc),
            address(weth),
            address(wsteth),
            address(veBAL),
            address(waDAI),
            address(usdt),
            address(waUSDC)
        ].toMemoryArray().asIERC20();
        MockMomentumRule momentumRule = new MockMomentumRule(owner);

        uint32[] memory weights = new uint32[](8);
        weights[0] = uint32(uint256(0.125e18));
        weights[1] = uint32(uint256(0.125e18));
        weights[2] = uint32(uint256(0.125e18));
        weights[3] = uint32(uint256(0.125e18));
        weights[4] = uint32(uint256(0.125e18));
        weights[5] = uint32(uint256(0.125e18));
        weights[6] = uint32(uint256(0.125e18));
        weights[7] = uint32(uint256(0.125e18));

        int256[] memory initialWeights = new int256[](8);
        initialWeights[0] = 0.125e18;
        initialWeights[1] = 0.125e18;
        initialWeights[2] = 0.125e18;
        initialWeights[3] = 0.125e18;
        initialWeights[4] = 0.125e18;
        initialWeights[5] = 0.125e18;
        initialWeights[6] = 0.125e18;
        initialWeights[7] = 0.125e18;

        uint256[] memory initialWeightsUint = new uint256[](8);
        initialWeightsUint[0] = 0.125e18;
        initialWeightsUint[1] = 0.125e18;
        initialWeightsUint[2] = 0.125e18;
        initialWeightsUint[3] = 0.125e18;
        initialWeightsUint[4] = 0.125e18;
        initialWeightsUint[5] = 0.125e18;
        initialWeightsUint[6] = 0.125e18;
        initialWeightsUint[7] = 0.125e18;

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
                new IERC20[](8),
                IUpdateRule(momentumRule),
                oracles,
                60,
                lambdas,
                0.01e18,
                0.01e18,
                0.01e18,
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
}
