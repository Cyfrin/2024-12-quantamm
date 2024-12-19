// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { E2eSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwap.t.sol";

import { QuantAMMWeightedPoolContractsDeployer } from "../utils/QuantAMMWeightedPoolContractsDeployer.sol";

contract E2eSwapQuantAMMTest is E2eSwapTest, QuantAMMWeightedPoolContractsDeployer {
    using FixedPoint for uint256;

    function setUp() public override {
        E2eSwapTest.setUp();
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by FungibilityTest.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address newPool, bytes memory poolArgs)  {
        IRateProvider[] memory rateProviders;
        return createQuantAMMPool(tokens, label, rateProviders, vault, lp);
    }

    function calculateMinAndMaxSwapAmounts() internal override {
        minSwapAmountTokenA = poolInitAmountTokenA / 1e3;
        minSwapAmountTokenB = poolInitAmountTokenB / 1e3;

        // Divide init amount by 10 to make sure weighted math ratios are respected (Cannot trade more than 30% of pool
        // balance).
        maxSwapAmountTokenA = poolInitAmountTokenA / 10;
        maxSwapAmountTokenB = poolInitAmountTokenB / 10;
    }

    function setUpVariables() internal override {
        sender = lp;
        poolCreator = lp;

        // 0.0001% min swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 10e16;
    }
}
