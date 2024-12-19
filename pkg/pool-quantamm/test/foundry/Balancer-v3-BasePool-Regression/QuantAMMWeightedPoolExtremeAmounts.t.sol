// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { QuantAMMWeightedPoolContractsDeployer } from "../utils/QuantAMMWeightedPoolContractsDeployer.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { BaseExtremeAmountsTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseExtremeAmountsTest.sol";

contract QuantAMMWeightedPoolExtremeAmountsTest is BaseExtremeAmountsTest, QuantAMMWeightedPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by FungibilityTest.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address newPool, bytes memory poolArgs)  {
        IRateProvider[] memory rateProviders;
        return createQuantAMMPool(tokens, label, rateProviders, vault, lp);
    }
}
