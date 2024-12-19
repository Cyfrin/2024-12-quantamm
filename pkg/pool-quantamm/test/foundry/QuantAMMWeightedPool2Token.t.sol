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
import { PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { OracleWrapper } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";
import { MockUpdateWeightRunner } from "../../contracts/mock/MockUpdateWeightRunner.sol";
import { MockMomentumRule } from "../../contracts/mock/mockRules/MockMomentumRule.sol";
import { MockChainlinkOracle } from "../../contracts/mock/MockChainlinkOracles.sol";

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";

contract QuantAMMWeightedPool2TokenTest is QuantAMMWeightedPoolContractsDeployer, BaseVaultTest {
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

    function testQuantAMMWeightedPoolGetNormalizedWeightsInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params._initialWeights[0] = 0.6e18;
        params._initialWeights[1] = 0.4e18;

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.6e18);
        assertEq(weights[1], 0.4e18);
    }

    function testGetNormalizedWeightSetWeightInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0e18;
        newWeights[3] = 0e18;

        vm.prank(address(updateWeightRunner));
        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.6e18);
        assertEq(weights[1], 0.4e18);
    }

    function testSetPoolDetailsThrowIfTooLarge(uint size) public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.poolDetails = new string[][](bound(size, 51,100));

        vm.expectRevert();
        quantAMMWeightedPoolFactory.create(params);

    }

    function testSetPoolDetailsThrowIfWrongShapeTooShort(uint size) public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.poolDetails = new string[][](1);
        params.poolDetails[0] = new string[](bound(size, 0,3));

        vm.expectRevert();
        quantAMMWeightedPoolFactory.create(params);
    }

    function testSetPoolDetailsThrowIfWrongShapeTooLong(uint size) public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.poolDetails = new string[][](1);
        params.poolDetails[0] = new string[](bound(size, 5,10));//could make longer but resource intensive

        vm.expectRevert();
        quantAMMWeightedPoolFactory.create(params);
    }

    function testSetPoolDetailsAcceptEmpty() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        quantAMMWeightedPoolFactory.create(params);
    }

    function testGetPoolDetailsEmptyDetailsNotFound() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        (string memory retType, string memory name) = IQuantAMMWeightedPool(quantAMMWeightedPool).getPoolDetail("some category", "some name");

        assertEq(retType, "error");
        assertEq(name, "detail not found");
    }

    function testGetPoolDetailSuccess() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.poolDetails = new string[][](1);
        params.poolDetails[0] = new string[](4);

        params.poolDetails[0][0] = "some category";
        params.poolDetails[0][1] = "some name";
        params.poolDetails[0][2] = "number";
        params.poolDetails[0][3] = "lambda value";

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        (string memory retType, string memory name) = IQuantAMMWeightedPool(quantAMMWeightedPool).getPoolDetail("some category", "some name");

        assertEq(retType, "number");
        assertEq(name, "lambda value");
    }

    function testGetPoolDetailsCategoryNotFound() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.poolDetails = new string[][](1);
        params.poolDetails[0] = new string[](4);

        params.poolDetails[0][0] = "some other category";
        params.poolDetails[0][1] = "some name";
        params.poolDetails[0][2] = "number";
        params.poolDetails[0][3] = "lambda value";

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        (string memory retType, string memory name) = IQuantAMMWeightedPool(quantAMMWeightedPool).getPoolDetail("some category", "some name");

        assertEq(retType, "error");
        assertEq(name, "detail not found");
    }

    function testGetPoolDetailsNameNotFound() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();
        params.poolDetails = new string[][](1);
        params.poolDetails[0] = new string[](4);

        params.poolDetails[0][0] = "some category";
        params.poolDetails[0][1] = "some other name";
        params.poolDetails[0][2] = "number";
        params.poolDetails[0][3] = "lambda value";

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        (string memory retType, string memory name) = IQuantAMMWeightedPool(quantAMMWeightedPool).getPoolDetail("some category", "some name");

        assertEq(retType, "error");
        assertEq(name, "detail not found");
    }

    function testSetWeightNBlocksAfter() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 2);

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.6e18 + 0.002e18);
        assertEq(weights[1], 0.4e18 + 0.002e18);
    }

    function testSetWeightAfterLimit() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 7);

        uint256[] memory weights = QuantAMMWeightedPool(quantAMMWeightedPool).getNormalizedWeights();

        assertEq(weights[0], 0.6e18 + 0.005e18);
        assertEq(weights[1], 0.4e18 + 0.005e18);
    }

    function testComputeBalanceInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0e18;
        newWeights[3] = 0e18;

        vm.prank(address(updateWeightRunner));
        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).computeBalance(balances, 0, uint256(1.2e18));

        assertEq(newBalance, 1355.091881588694578000e18);
    }

    function testComputeBalanceNBlocksAfter() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 2);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).computeBalance(balances, 0, uint256(1.2e18));

        assertEq(newBalance, 1353.724562681596718000e18);
    }

    function testComputeBalanceAfterLimit() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 7);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).computeBalance(balances, 0, uint256(1.2e18));

        assertEq(newBalance, 1351.693086891767401000e18);
    }

    function testOnSwapOutGivenInInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0e18;
        newWeights[3] = 0e18;

        vm.prank(address(updateWeightRunner));
        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 100e18,
            balancesScaled18: balances,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, 266.431655917087542000e18);
    }

    function testOnSwapOutGivenInNBlocksAfter() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 2);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 100e18,
            balancesScaled18: balances,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, 266.020595471997916000e18);
    }

    function testOnSwapOutGivenInAfterLimit() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 7);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 100e18,
            balancesScaled18: balances,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, 265.411437865277198000e18);
    }

    function testOnSwapInGivenOutInitial() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0e18;
        newWeights[3] = 0e18;

        vm.prank(address(updateWeightRunner));
        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: 100e18,
            balancesScaled18: balances,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, 34.786918412177192000e18);
    }

    function testOnSwapInGivenOutNBlocksAfter() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 2);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: 100e18,
            balancesScaled18: balances,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, 34.845699295402889000e18);
    }

    function testOnSwapInGivenOutAfterLimit() public {
        QuantAMMWeightedPoolFactory.NewPoolParams memory params = _createPoolParams();

        (address quantAMMWeightedPool, ) = quantAMMWeightedPoolFactory.create(params);

        vm.prank(address(updateWeightRunner));
        int256[] memory newWeights = new int256[](4);
        newWeights[0] = 0.6e18;
        newWeights[1] = 0.4e18;
        newWeights[2] = 0.001e18;
        newWeights[3] = 0.001e18;

        QuantAMMWeightedPool(quantAMMWeightedPool).setWeights(
            newWeights,
            quantAMMWeightedPool,
            uint40(block.timestamp + 5)
        );

        vm.warp(block.timestamp + 7);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 2000e18;

        PoolSwapParams memory swapParams = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: 100e18,
            balancesScaled18: balances,
            indexIn: 0,
            indexOut: 1,
            router: address(router),
            userData: abi.encode(0)
        });
        vm.prank(address(vault));
        uint256 newBalance = QuantAMMWeightedPool(quantAMMWeightedPool).onSwap(swapParams);

        assertEq(newBalance, 34.933148109829107000e18);
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
}
