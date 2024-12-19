// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FungibilityTest } from "@balancer-labs/v3-vault/test/foundry/Fungibility.t.sol";

import { QuantAMMWeightedPoolContractsDeployer } from "../utils/QuantAMMWeightedPoolContractsDeployer.sol";

contract FungibilityQuantAMMTest is FungibilityTest, QuantAMMWeightedPoolContractsDeployer {
    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by FungibilityTest.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address newPool, bytes memory poolArgs)  {
        IRateProvider[] memory rateProviders;
        return createQuantAMMPool(tokens, label, rateProviders, vault, lp);
    }
}
