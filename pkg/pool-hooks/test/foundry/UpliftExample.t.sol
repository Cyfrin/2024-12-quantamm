// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    LiquidityManagement,
    PoolRoleAccounts,
    RemoveLiquidityKind,
    AfterSwapParams,
    SwapKind,
    AddLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-vault/contracts/test/BasicAuthorizerMock.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { BatchRouterMock } from "@balancer-labs/v3-vault/contracts/test/BatchRouterMock.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { RouterMock } from "@balancer-labs/v3-vault/contracts/test/RouterMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { MockUpdateWeightRunner } from "pool-quantamm/contracts/mock/MockUpdateWeightRunner.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { UpliftOnlyExample } from "../../contracts/hooks-quantamm/UpliftOnlyExample.sol";
import { LPNFT } from "../../contracts/hooks-quantamm/LPNFT.sol";

contract UpliftOnlyExampleTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    address internal owner;
    address internal addr1;
    address internal addr2;

    // Maximum exit fee of 10%
    uint64 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint64 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%
    uint64 private constant _MAX_UPLIFT_WITHDRAWAL_FEE = 20e16; // 20%

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    MockUpdateWeightRunner internal updateWeightRunner;

    UpliftOnlyExample internal upliftOnlyRouter;

    // Overrides `setUp` to include a deployment for UpliftOnlyExample.
    function setUp() public virtual override {
        BaseTest.setUp();
        (address ownerLocal, address addr1Local, address addr2Local) = (vm.addr(1), vm.addr(2), vm.addr(3));
        owner = ownerLocal;
        addr1 = addr1Local;
        addr2 = addr2Local;

        vault = deployVaultMock();
        vm.label(address(vault), "vault");
        vaultExtension = IVaultExtension(vault.getVaultExtension());
        vm.label(address(vaultExtension), "vaultExtension");
        vaultAdmin = IVaultAdmin(vault.getVaultAdmin());
        vm.label(address(vaultAdmin), "vaultAdmin");
        authorizer = BasicAuthorizerMock(address(vault.getAuthorizer()));
        vm.label(address(authorizer), "authorizer");
        factoryMock = PoolFactoryMock(address(vault.getPoolFactoryMock()));
        vm.label(address(factoryMock), "factory");
        router = deployRouterMock(IVault(address(vault)), weth, permit2);
        vm.label(address(router), "router");
        batchRouter = deployBatchRouterMock(IVault(address(vault)), weth, permit2);
        vm.label(address(batchRouter), "batch router");
        feeController = vault.getProtocolFeeController();
        vm.label(address(feeController), "fee controller");

        vm.startPrank(address(vaultAdmin));
        updateWeightRunner = new MockUpdateWeightRunner(address(vaultAdmin), address(addr2), true);
        vm.label(address(updateWeightRunner), "updateWeightRunner");
        updateWeightRunner.setQuantAMMSwapFeeTake(0);

        vm.stopPrank();

        vm.startPrank(owner);
        upliftOnlyRouter = new UpliftOnlyExample(
            IVault(address(vault)),
            weth,
            permit2,
            200,
            5,
            address(updateWeightRunner),
            "Uplift LiquidityPosition v1",
            "Uplift LiquidityPosition v1",
            "Uplift LiquidityPosition v1"
        );
        vm.stopPrank();
        vm.label(address(upliftOnlyRouter), "upliftOnlyRouter");

        // Here the Router is also the hook.
        poolHooksContract = address(upliftOnlyRouter);
        (pool, ) = createPool();

        // Approve vault allowances.
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            vm.startPrank(user);
            approveForSender();
            vm.stopPrank();
        }
        if (pool != address(0)) {
            approveForPool(IERC20(pool));
        }
        // Add initial liquidity.
        initPool();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // Overrides approval to include upliftOnlyRouter.
    function approveForSender() internal override {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(tokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(tokens[i]), address(batchRouter), type(uint160).max, type(uint48).max);
            permit2.approve(address(tokens[i]), address(upliftOnlyRouter), type(uint160).max, type(uint48).max);
        }
    }

    // Overrides approval to include upliftOnlyRouter.
    function approveForPool(IERC20 bpt) internal override {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);

            bpt.approve(address(router), type(uint256).max);
            bpt.approve(address(batchRouter), type(uint256).max);
            bpt.approve(address(upliftOnlyRouter), type(uint256).max);

            IERC20(bpt).approve(address(permit2), type(uint256).max);
            permit2.approve(address(bpt), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(batchRouter), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(upliftOnlyRouter), type(uint160).max, type(uint48).max);

            vm.stopPrank();
        }
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity).
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Uplift Pool";
        string memory symbol = "Uplift Pool";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, label);
        int256[] memory prices = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            prices[i] = int256(i) * 1e18;
        }
        updateWeightRunner.setMockPrices(address(newPool), prices);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;
        liquidityManagement.enableDonation = true;

        factoryMock.registerPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function testAddLiquidity() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        uint256[] memory amountsIn = upliftOnlyRouter.addLiquidityProportional(
            pool,
            maxAmountsIn,
            bptAmount,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        // Bob sends correct lp tokens
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            amountsIn[daiIdx],
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.bobTokens[usdcIdx] - balancesAfter.bobTokens[usdcIdx],
            amountsIn[usdcIdx],
            "bob's USDC amount is wrong"
        );
        // Router should set correct lp data
        uint256 expectedTokenId = 1;

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "deposit length incorrect");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount incorrect");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "blockTimestampDeposit incorrect"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        assertEq(upliftOnlyRouter.nftPool(expectedTokenId), pool, "pool mapping is wrong");

        // Router should receive BPT instead of bob, he gets the NFT
        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            bptAmount,
            "UpliftOnlyRouter should hold BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testAddLiquidityMultipleDeposits() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        uint256[] memory amountsInFirst = upliftOnlyRouter.addLiquidityProportional(
            pool,
            maxAmountsIn,
            bptAmount / 2,
            false,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory prices = new int256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            prices[i] = (int256(i) * 1e18) / 2;
        }
        updateWeightRunner.setMockPrices(pool, prices);

        skip(5 days);

        vm.prank(bob);
        uint256[] memory amountsInSecond = upliftOnlyRouter.addLiquidityProportional(
            pool,
            maxAmountsIn,
            bptAmount / 2,
            false,
            bytes("")
        );
        vm.stopPrank();

        uint256[] memory amountsIn = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            amountsIn[i] = amountsInFirst[i] + amountsInSecond[i];
        }

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        // Bob sends correct lp tokens
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            amountsIn[daiIdx],
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.bobTokens[usdcIdx] - balancesAfter.bobTokens[usdcIdx],
            amountsIn[usdcIdx],
            "bob's USDC amount is wrong"
        );

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 2, "deposit length incorrect");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount / 2, "bptAmount incorrect");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            1682899200,
            "blockTimestampDeposit incorrect"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[1].amount, bptAmount / 2, "bptAmount incorrect");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[1].blockTimestampDeposit,
            1683331200,
            "blockTimestampDeposit incorrect"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[1].lpTokenDepositValue,
            250000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[1].upliftFeeBps, 200, "fee");

        assertEq(upliftOnlyRouter.nftPool(1), pool, "pool mapping is wrong");
        assertEq(upliftOnlyRouter.nftPool(2), pool, "pool mapping is wrong");
        // Router should receive BPT instead of bob, he gets the NFT
        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            bptAmount,
            "UpliftOnlyRouter should hold BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testAddLiquidityThrowOnLimitDeposits() public {
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.startPrank(bob);
        uint256 bptAmountDeposit = bptAmount / 150;
        for (uint256 i = 0; i < 150; i++) {
            if (i == 101) {
                vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.TooManyDeposits.selector, pool, bob));
                upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmountDeposit, false, bytes(""));
                break;
            } else {
                upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmountDeposit, false, bytes(""));
            }

            skip(1 days);
        }
        vm.stopPrank();
    }

    function testTransferDepositsAtRandom(uint256 seed, uint256 depositLength) public {
        uint256 depositBound = bound(depositLength, 1, 10);
        /**
         * This can be changed to the max 98 however it takes some time!
         * uint256 depositBound = bound(depositLength, 1, 98);
         * [PASS] testTransferDepositsAtRandom(uint256,uint256) (runs: 10002, μ: 119097137, ~: 78857000)
            Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 1233.99s (1233.98s CPU time)

            Ran 1 test suite in 1234.00s (1233.99s CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)
         * 
         */
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.startPrank(bob);
        uint256 bptAmountDeposit = bptAmount / 150;
        uint256[] memory tokenIndexArray = new uint256[](depositBound);
        for (uint256 i = 0; i < depositBound; i++) {
            tokenIndexArray[i] = i + 1;
            upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmountDeposit, false, bytes(""));
            skip(1 days);
        }
        vm.stopPrank();

        // Shuffle the array using the seed
        uint[] memory shuffledArray = shuffle(tokenIndexArray, seed);

        LPNFT lpNft = upliftOnlyRouter.lpNFT();

        for (uint256 i = 0; i < depositBound; i++) {
            vm.startPrank(bob);

            lpNft.transferFrom(bob, alice, shuffledArray[i]);
            UpliftOnlyExample.FeeData[] memory aliceFees = upliftOnlyRouter.getUserPoolFeeData(pool, alice);
            UpliftOnlyExample.FeeData[] memory bobFees = upliftOnlyRouter.getUserPoolFeeData(pool, bob);

            assertEq(aliceFees.length, i + 1, "alice should have all transfers");
            assertEq(
                aliceFees[aliceFees.length - 1].tokenID,
                shuffledArray[i],
                "last transferred tokenId should match"
            );

            assertEq(bobFees.length, depositBound - (i + 1), "bob should have all transferred last");

            uint[] memory orderedArrayWithoutShuffled = new uint[](depositBound - (i + 1));
            uint lastPopulatedIndex = 0;
            for (uint256 j = 1; j <= depositBound; j++) {
                bool inPreviousShuffled = false;
                for (uint256 k = 0; k < i + 1; k++) {
                    if (shuffledArray[k] == j) {
                        inPreviousShuffled = true;
                        break;
                    }
                }
                if (!inPreviousShuffled) {
                    orderedArrayWithoutShuffled[lastPopulatedIndex] = j;
                    lastPopulatedIndex++;
                }
            }

            for (uint256 j = 0; j < bobFees.length; j++) {
                assertEq(bobFees[j].tokenID, orderedArrayWithoutShuffled[j], "bob should have ordered tokenID");
            }

            vm.stopPrank();
        }
    }

    //Function to generate a shuffled array of unique uints between 0 and 10
    function shuffle(uint[] memory array, uint seed) internal pure returns (uint[] memory) {
        uint length = array.length;
        for (uint i = length - 1; i > 0; i--) {
            uint j = seed % (i + 1); // Pseudo-random index based on the seed
            (array[i], array[j]) = (array[j], array[i]); // Swap elements
            seed /= (i + 1); // Adjust seed to vary indices in next iteration
        }
        return array;
    }

    function testRemoveLiquidityNoPriceChange() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();

        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "bptAmount mapping should be 1");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount mapping should be 0");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "bptAmount mapping should be 0"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.startPrank(bob);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
        vm.stopPrank();
        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        uint256 feeAmountAmountPercent = ((bptAmount / 2) *
            ((uint256(upliftOnlyRouter.minWithdrawalFeeBps()) * 1e18) / 10000)) / ((bptAmount / 2));
        uint256 amountOut = (bptAmount / 2).mulDown((1e18 - feeAmountAmountPercent));

        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );

        //As the bpt value taken in fees is readded to the pool under the router address, the pool supply should remain the same
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, bptAmount, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        //User has extracted deposit, now deposit was deleted and popped from the mapping
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.bptAmount(nftTokenId), 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");

        assertEq(upliftOnlyRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            0,
            "upliftOnlyRouter should hold no BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveLiquidityNegativePriceChange() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "bptAmount mapping should be 1");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount mapping should be 0");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "bptAmount mapping should be 0"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        int256[] memory prices = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            prices[i] = int256(i) / 2;
        }
        updateWeightRunner.setMockPrices(pool, prices);

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.startPrank(bob);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
        vm.stopPrank();
        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        uint256 feeAmountAmountPercent = ((bptAmount / 2) *
            ((uint256(upliftOnlyRouter.minWithdrawalFeeBps()) * 1e18) / 10000)) / ((bptAmount / 2));
        uint256 amountOut = (bptAmount / 2).mulDown((1e18 - feeAmountAmountPercent));

        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );

        //As the bpt value taken in fees is readded to the pool under the router address, the pool supply should remain the same
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, bptAmount, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        //User has extracted deposit, now deposit was deleted and popped from the mapping
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.bptAmount(nftTokenId), 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");

        assertEq(upliftOnlyRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            0,
            "upliftOnlyRouter should hold no BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveLiquidityDoublePositivePriceChange() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "bptAmount mapping should be 1");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount mapping should be 0");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "bptAmount mapping should be 0"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        int256[] memory prices = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            prices[i] = int256(i) * 2e18;
        }
        updateWeightRunner.setMockPrices(pool, prices);

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.startPrank(bob);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
        vm.stopPrank();
        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        uint256 feeAmountAmountPercent = ((bptAmount / 2) *
            ((uint256(upliftOnlyRouter.upliftFeeBps()) * 1e18) / 10000)) / ((bptAmount / 2));

        /* 
            Bob has doubled his value. 
            Uplift fee is taken on only the uplift. 
            Given each BPT is worth double now, the fee is 2% of the original value.
            Bob has 1000e18 in BPT, so the fee is 20e18.
            Bob should get 980e18 in DAI and USDC.
        */

        uint256 amountOut = (bptAmount / 2).mulDown((1e18 - feeAmountAmountPercent));

        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );

        //As the bpt value taken in fees is readded to the pool under the router address, the pool supply should remain the same
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, bptAmount, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        //User has extracted deposit, now deposit was deleted and popped from the mapping
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.bptAmount(nftTokenId), 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");

        assertEq(upliftOnlyRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            0,
            "upliftOnlyRouter should hold no BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveWithNonOwner() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        // Remove fails because lp isn't the owner of the NFT.
        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.WithdrawalByNonOwner.selector, lp, pool, bptAmount));
        vm.prank(lp);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
    }

    function testAddFromExternalRouter() public {
        // Add fails because it must be done via NftLiquidityPositionExample.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.CannotUseExternalRouter.selector, router));
        vm.prank(bob);
        router.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
    }

    function testRemoveFromExternalRouter() public {
        uint256 amountOut = poolInitAmount / 2;
        uint256[] memory minAmountsOut = [amountOut, amountOut].toMemoryArray();

        vm.expectRevert(
            abi.encodeWithSelector(UpliftOnlyExample.WithdrawalByNonOwner.selector, lp, pool, amountOut * 2)
        );
        vm.startPrank(lp);
        upliftOnlyRouter.removeLiquidityProportional(amountOut * 2, minAmountsOut, false, pool);
        vm.stopPrank();
    }

    function testOnAfterRemoveLiquidityFromExternalRouterWithRealDepositor() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.CannotUseExternalRouter.selector, router));
        vm.startPrank(bob);
        upliftOnlyRouter.onAfterRemoveLiquidity(
            address(router),
            pool,
            RemoveLiquidityKind.PROPORTIONAL,
            bptAmount,
            minAmountsOut,
            minAmountsOut,
            minAmountsOut,
            bytes("")
        );
        vm.stopPrank();
    }

    function testOnAfterRemoveLiquidityFromExternalRouterWithRandomExternal() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.CannotUseExternalRouter.selector, router));
        vm.startPrank(lp);
        upliftOnlyRouter.onAfterRemoveLiquidity(
            address(router),
            pool,
            RemoveLiquidityKind.PROPORTIONAL,
            bptAmount,
            minAmountsOut,
            minAmountsOut,
            minAmountsOut,
            bytes("")
        );
        vm.stopPrank();
    }

    function testOnBeforeAddLiquidityFromExternalRouterWithRealDepositor() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.CannotUseExternalRouter.selector, router));
        vm.startPrank(bob);
        upliftOnlyRouter.onBeforeAddLiquidity(
            address(router),
            pool,
            AddLiquidityKind.PROPORTIONAL,
            minAmountsOut,
            bptAmount,
            minAmountsOut,
            bytes("")
        );
        vm.stopPrank();
    }

    function testOnBeforeAddLiquidityFromExternalRouterWithRandomExternal() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.CannotUseExternalRouter.selector, router));
        vm.startPrank(lp);
        upliftOnlyRouter.onBeforeAddLiquidity(
            address(router),
            pool,
            AddLiquidityKind.PROPORTIONAL,
            minAmountsOut,
            bptAmount,
            minAmountsOut,
            bytes("")
        );
        vm.stopPrank();
    }

    function testAfterUpdateFromExternalRouterWithRealDepositor() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.TransferUpdateNonNft.selector, lp, bob, bob, 1));
        vm.startPrank(bob);
        upliftOnlyRouter.afterUpdate(lp, bob, 1);
        vm.stopPrank();
    }

    function testAfterUpdateFromExternalRouterWithRandomExternal() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.TransferUpdateNonNft.selector, bob, lp, lp, 1));
        vm.startPrank(lp);
        upliftOnlyRouter.afterUpdate(bob, lp, 1);
        vm.stopPrank();
    }

    function testAfterUpdateFromExternalRouterWithRouter() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.TransferUpdateNonNft.selector, bob, lp, router, 1));
        vm.startPrank(address(router));
        upliftOnlyRouter.afterUpdate(bob, lp, 1);
        vm.stopPrank();
    }

    function testAfterUpdateFromNFTInvalidTokenID() public {
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        vm.startPrank(address(upliftOnlyRouter.lpNFT()));
        vm.expectRevert(abi.encodeWithSelector(UpliftOnlyExample.TransferUpdateTokenIDInvaid.selector, bob, lp, 2));
        upliftOnlyRouter.afterUpdate(bob, lp, 2);
        vm.stopPrank();
    }

    function testSetHookFeeNonOwnerFail() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vm.startPrank(bob);
        upliftOnlyRouter.setHookSwapFeePercentage(1);
        vm.stopPrank();
    }

    function testSetHookFeeOwnerPass(uint64 poolHookAmount) public {
        uint64 boundFeeAmount = uint64(bound(poolHookAmount, _MIN_SWAP_FEE_PERCENTAGE, _MAX_SWAP_FEE_PERCENTAGE));
        vm.expectEmit();
        emit UpliftOnlyExample.HookSwapFeePercentageChanged(poolHooksContract, boundFeeAmount);
        vm.startPrank(owner);
        upliftOnlyRouter.setHookSwapFeePercentage(boundFeeAmount);
        vm.stopPrank();
    }

    function testSetHookPassSmallerThanMinimumFail(uint64 poolHookAmount) public {
        uint64 boundFeeAmount = uint64(bound(poolHookAmount, 0, _MIN_SWAP_FEE_PERCENTAGE - 1));

        vm.startPrank(owner);
        vm.expectRevert("Below _MIN_SWAP_FEE_PERCENTAGE");
        upliftOnlyRouter.setHookSwapFeePercentage(boundFeeAmount);
        vm.stopPrank();
    }

    function testSetHookPassGreaterThanMaxFail(uint64 poolHookAmount) public {
        uint64 boundFeeAmount = uint64(bound(poolHookAmount, uint64(_MAX_SWAP_FEE_PERCENTAGE) + 1, uint64(type(uint64).max)));

        vm.startPrank(owner);
        vm.expectRevert("Above _MAX_SWAP_FEE_PERCENTAGE");
        upliftOnlyRouter.setHookSwapFeePercentage(boundFeeAmount);
        vm.stopPrank();
    }

    function testFeeSwapExactIn__Fuzz(uint256 swapAmount, uint64 hookFeePercentage) public {
        // Swap between POOL_MINIMUM_TOTAL_SUPPLY and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, POOL_MINIMUM_TOTAL_SUPPLY, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = uint64(bound(hookFeePercentage, _MIN_SWAP_FEE_PERCENTAGE, _MAX_SWAP_FEE_PERCENTAGE));

        vm.expectEmit();
        emit UpliftOnlyExample.HookSwapFeePercentageChanged(poolHooksContract, hookFeePercentage);

        vm.prank(owner);
        UpliftOnlyExample(payable(poolHooksContract)).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulUp(hookFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeCall(
                IHooks.onAfterSwap,
                AfterSwapParams({
                    kind: SwapKind.EXACT_IN,
                    tokenIn: dai,
                    tokenOut: usdc,
                    amountInScaled18: swapAmount,
                    amountOutScaled18: swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - swapAmount,
                    amountCalculatedScaled18: swapAmount,
                    amountCalculatedRaw: swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: bytes("")
                })
            )
        );

        if (hookFee > 0) {
            vm.expectEmit();
            emit UpliftOnlyExample.SwapHookFeeCharged(poolHooksContract, IERC20(usdc), hookFee);
        }

        router.swapSingleTokenExactIn(address(pool), dai, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            swapAmount,
            "Bob DAI balance is wrong"
        );
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook DAI balance is wrong");
        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            swapAmount - hookFee,
            "Bob USDC balance is wrong"
        );
        assertEq(
            balancesAfter.hookTokens[usdcIdx] - balancesBefore.hookTokens[usdcIdx],
            hookFee,
            "Hook USDC balance is wrong"
        );

        _checkPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, swapAmount);
    }

    function testFeeSwapExactOut__Fuzz(uint256 swapAmount, uint64 hookFeePercentage) public {
        // Swap between POOL_MINIMUM_TOTAL_SUPPLY and whole pool liquidity (pool math is linear)
        swapAmount = bound(swapAmount, POOL_MINIMUM_TOTAL_SUPPLY, poolInitAmount);

        // Fee between 0 and 100%
        hookFeePercentage = uint64(bound(hookFeePercentage, _MIN_SWAP_FEE_PERCENTAGE, _MAX_SWAP_FEE_PERCENTAGE));

        vm.expectEmit();
        emit UpliftOnlyExample.HookSwapFeePercentageChanged(poolHooksContract, hookFeePercentage);

        vm.prank(owner);
        UpliftOnlyExample(payable(poolHooksContract)).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulUp(hookFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.prank(bob);
        vm.expectCall(
            address(poolHooksContract),
            abi.encodeCall(
                IHooks.onAfterSwap,
                AfterSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    tokenIn: dai,
                    tokenOut: usdc,
                    amountInScaled18: swapAmount,
                    amountOutScaled18: swapAmount,
                    tokenInBalanceScaled18: poolInitAmount + swapAmount,
                    tokenOutBalanceScaled18: poolInitAmount - swapAmount,
                    amountCalculatedScaled18: swapAmount,
                    amountCalculatedRaw: swapAmount,
                    router: address(router),
                    pool: pool,
                    userData: bytes("")
                })
            )
        );

        if (hookFee > 0) {
            vm.expectEmit();
            emit UpliftOnlyExample.SwapHookFeeCharged(poolHooksContract, IERC20(dai), hookFee);
        }

        router.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            swapAmount,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        assertEq(
            balancesAfter.userTokens[usdcIdx] - balancesBefore.userTokens[usdcIdx],
            swapAmount,
            "Bob USDC balance is wrong"
        );
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook USDC balance is wrong");
        assertEq(
            balancesBefore.userTokens[daiIdx] - balancesAfter.userTokens[daiIdx],
            swapAmount + hookFee,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesAfter.hookTokens[daiIdx] - balancesBefore.hookTokens[daiIdx],
            hookFee,
            "Hook DAI balance is wrong"
        );

        _checkPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, swapAmount);
    }

    function _checkPoolAndVaultBalancesAfterSwap(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256 poolBalanceChange
    ) private view {
        // Considers swap fee = 0, so only hook fees were charged
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            poolBalanceChange,
            "Pool DAI balance is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            poolBalanceChange,
            "Pool USDC balance is wrong"
        );
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            poolBalanceChange,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            poolBalanceChange,
            "Vault USDC balance is wrong"
        );
    }

    function testRemoveLiquidityWithProtocolTakeNoPriceChange() public {
        vm.prank(address(vaultAdmin));
        updateWeightRunner.setQuantAMMUpliftFeeTake(0.5e18);
        vm.stopPrank();

        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();

        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "bptAmount mapping should be 1");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount mapping should be 0");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "bptAmount mapping should be 0"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(updateWeightRunner.getQuantAMMAdmin());

        vm.startPrank(bob);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
        vm.stopPrank();
        BaseVaultTest.Balances memory balancesAfter = getBalances(updateWeightRunner.getQuantAMMAdmin());

        uint256 feeAmountAmountPercent = (((bptAmount / 2) *
            ((uint256(upliftOnlyRouter.minWithdrawalFeeBps()) * 1e18) / 10000)) / ((bptAmount / 2)));
        uint256 amountOut = (bptAmount / 2).mulDown((1e18 - feeAmountAmountPercent));

        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );

        //As the bpt value taken in fees is readded to the pool under the router address, the pool supply should remain the same
        assertEq(
            balancesBefore.poolSupply - balancesAfter.poolSupply,
            bptAmount - balancesAfter.userBpt,
            "BPT supply amount is wrong"
        );

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        //User has extracted deposit, now deposit was deleted and popped from the mapping
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.bptAmount(nftTokenId), 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");

        assertEq(upliftOnlyRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            0,
            "upliftOnlyRouter should hold no BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");

        // was originall 1000000000000000000, doubled in value to 2000000000000000000,
        //total fee was 50% of uplift which is 1000000000000000000, of that fee the protocol take 50% which is 500000000000000000
        assertEq(balancesAfter.userBpt, 500000000000000000, "quantamm should not hold any BPT");
    }

    function testRemoveLiquidityWithProtocolTakeNegativePriceChange() public {
        vm.prank(address(vaultAdmin));
        updateWeightRunner.setQuantAMMUpliftFeeTake(0.5e18);
        vm.stopPrank();

        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "bptAmount mapping should be 1");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount mapping should be 0");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "bptAmount mapping should be 0"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        int256[] memory prices = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            prices[i] = int256(i) / 2;
        }
        updateWeightRunner.setMockPrices(pool, prices);

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(updateWeightRunner.getQuantAMMAdmin());

        vm.startPrank(bob);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
        vm.stopPrank();
        BaseVaultTest.Balances memory balancesAfter = getBalances(updateWeightRunner.getQuantAMMAdmin());

        uint256 feeAmountAmountPercent = ((bptAmount / 2) *
            ((uint256(upliftOnlyRouter.minWithdrawalFeeBps()) * 1e18) / 10000)) / ((bptAmount / 2));
        uint256 amountOut = (bptAmount / 2).mulDown((1e18 - feeAmountAmountPercent));

        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );

        //As the bpt value taken in fees is readded to the pool under the router address, the pool supply should remain the same
        assertEq(
            balancesBefore.poolSupply - balancesAfter.poolSupply,
            bptAmount - balancesAfter.userBpt,
            "BPT supply amount is wrong"
        );

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        //User has extracted deposit, now deposit was deleted and popped from the mapping
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.bptAmount(nftTokenId), 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");

        assertEq(upliftOnlyRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            0,
            "upliftOnlyRouter should hold no BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }

    function testRemoveLiquidityWithProtocolTakeDoublePositivePriceChange() public {
        vm.prank(address(vaultAdmin));
        updateWeightRunner.setQuantAMMUpliftFeeTake(0.5e18);
        vm.stopPrank();
        // Add liquidity so bob has BPT to remove liquidity.
        uint256[] memory maxAmountsIn = [dai.balanceOf(bob), usdc.balanceOf(bob)].toMemoryArray();
        vm.prank(bob);
        upliftOnlyRouter.addLiquidityProportional(pool, maxAmountsIn, bptAmount, false, bytes(""));
        vm.stopPrank();

        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 1, "bptAmount mapping should be 1");
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].amount, bptAmount, "bptAmount mapping should be 0");
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].blockTimestampDeposit,
            block.timestamp,
            "bptAmount mapping should be 0"
        );
        assertEq(
            upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].lpTokenDepositValue,
            500000000000000000,
            "should match sum(amount * price)"
        );
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob)[0].upliftFeeBps, 200, "fee");

        int256[] memory prices = new int256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            prices[i] = int256(i) * 2e18;
        }
        updateWeightRunner.setMockPrices(pool, prices);

        uint256 nftTokenId = 0;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(updateWeightRunner.getQuantAMMAdmin());

        vm.startPrank(bob);
        upliftOnlyRouter.removeLiquidityProportional(bptAmount, minAmountsOut, false, pool);
        vm.stopPrank();
        BaseVaultTest.Balances memory balancesAfter = getBalances(updateWeightRunner.getQuantAMMAdmin());

        uint256 feeAmountAmountPercent = ((bptAmount / 2) *
            ((uint256(upliftOnlyRouter.upliftFeeBps()) * 1e18) / 10000)) / ((bptAmount / 2));

        /* 
            Bob has doubled his value. 
            Uplift fee is taken on only the uplift. 
            Given each BPT is worth double now, the fee is 2% of the original value.
            Bob has 1000e18 in BPT, so the fee is 20e18.
            Bob should get 980e18 in DAI and USDC.
        */

        uint256 amountOut = (bptAmount / 2).mulDown((1e18 - feeAmountAmountPercent));

        // Bob gets original liquidity with no fee applied because of full decay.
        assertEq(
            balancesAfter.bobTokens[daiIdx] - balancesBefore.bobTokens[daiIdx],
            amountOut,
            "bob's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            amountOut,
            "bob's USDC amount is wrong"
        );

        // Pool balances decrease by amountOut.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountOut,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountOut,
            "Pool's USDC amount is wrong"
        );

        //As the bpt value taken in fees is readded to the pool under the router address, the pool supply should remain the same
        assertEq(
            balancesBefore.poolSupply - balancesAfter.poolSupply,
            bptAmount - balancesAfter.userBpt,
            "BPT supply amount is wrong"
        );

        // Same happens with Vault balances: decrease by amountOut.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountOut,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountOut,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");

        // Router should set all lp data to 0.
        //User has extracted deposit, now deposit was deleted and popped from the mapping
        assertEq(upliftOnlyRouter.getUserPoolFeeData(pool, bob).length, 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.bptAmount(nftTokenId), 0, "bptAmount mapping should be 0");
        //assertEq(upliftOnlyRouter.startTime(nftTokenId), 0, "startTime mapping should be 0");

        assertEq(upliftOnlyRouter.nftPool(nftTokenId), address(0), "pool mapping should be 0");

        assertEq(
            BalancerPoolToken(pool).balanceOf(address(upliftOnlyRouter)),
            0,
            "upliftOnlyRouter should hold no BPT"
        );
        assertEq(balancesAfter.bobBpt, 0, "bob should not hold any BPT");
    }
}
