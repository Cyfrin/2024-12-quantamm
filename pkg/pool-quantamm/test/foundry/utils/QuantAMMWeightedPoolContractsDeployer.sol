// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { PoolRoleAccounts, TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { BaseContractsDeployer } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseContractsDeployer.sol";

import { MockUpdateWeightRunner } from "../../../contracts/mock/MockUpdateWeightRunner.sol";
import { MockChainlinkOracle } from "../../../contracts/mock/MockChainlinkOracles.sol";
import { MockMomentumRule } from "../../../contracts/mock/mockRules/MockMomentumRule.sol";
import { MockQuantAMMWeightedPool } from "../../../contracts/mock/QuantAMMWeightedPoolMock.sol";
import { QuantAMMWeightedMathMock } from "../../../contracts/mock/QuantAMMWeightedMathMock.sol";
import { QuantAMMWeightedPool } from "../../../contracts/QuantAMMWeightedPool.sol";
import { QuantAMMWeightedPoolFactory } from "../../../contracts/QuantAMMWeightedPoolFactory.sol";

import { IQuantAMMWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IQuantAMMWeightedPool.sol";
import { IUpdateRule } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/IUpdateRule.sol";
import { OracleWrapper } from "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";

/**
 * @dev This contract contains functions for deploying mocks and contracts related to the "WeightedPool". These functions should have support for reusing artifacts from the hardhat compilation.
 */
contract QuantAMMWeightedPoolContractsDeployer is BaseContractsDeployer {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    string private artifactsRootDir = "artifacts/";

    MockUpdateWeightRunner internal updateWeightRunner;
    MockChainlinkOracle internal chainlinkOracle;

    address internal owner;
    address internal addr1;
    address internal addr2;

    address internal deployerFactory;

    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    function _deployOracle(int216 fixedValue, uint delay) internal returns (MockChainlinkOracle) {
        MockChainlinkOracle oracle = new MockChainlinkOracle(fixedValue, delay);
        return oracle;
    }

    constructor() {
        // if this external artifact path exists, it means we are running outside of this repo
        if (vm.exists("artifacts/@balancer-labs/v3-pool-quantamm/")) {
            artifactsRootDir = "artifacts/@balancer-labs/v3-pool-quantamm/";
        }
        (address ownerLocal, address addr1Local, address addr2Local) = (vm.addr(1), vm.addr(2), vm.addr(3));
        owner = ownerLocal;
        addr1 = addr1Local;
        addr2 = addr2Local;

        vm.startPrank(owner);
        updateWeightRunner = new MockUpdateWeightRunner(owner, addr2, false);

        chainlinkOracle = _deployOracle(1e18, 0);

        updateWeightRunner.addOracle(OracleWrapper(chainlinkOracle));

        vm.stopPrank();
    }

    function deployQuantAMMWeightedPoolFactory(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) internal returns (QuantAMMWeightedPoolFactory) {
        if (reusingArtifacts) {
            return
                QuantAMMWeightedPoolFactory(
                    deployCode(
                        _computeWeightedPath(type(QuantAMMWeightedPoolFactory).name),
                        abi.encode(vault, pauseWindowDuration, factoryVersion, poolVersion, updateWeightRunner)
                    )
                );
        } else {
            return
                new QuantAMMWeightedPoolFactory(
                    vault,
                    pauseWindowDuration,
                    factoryVersion,
                    poolVersion,
                    address(updateWeightRunner)
                );
        }
    }

    //taken out of IVault to avoid using the buildTokenConfig function
    function sortTokenConfig(TokenConfig[] memory tokenConfig) public pure returns (TokenConfig[] memory) {
        for (uint256 i = 0; i < tokenConfig.length - 1; ++i) {
            for (uint256 j = 0; j < tokenConfig.length - i - 1; j++) {
                if (tokenConfig[j].token > tokenConfig[j + 1].token) {
                    // Swap if they're out of order.
                    (tokenConfig[j], tokenConfig[j + 1]) = (tokenConfig[j + 1], tokenConfig[j]);
                }
            }
        }

        return tokenConfig;
    }
    function _createPoolParams(address[] memory tokens, IRateProvider[] memory rateProviders) internal returns (QuantAMMWeightedPoolFactory.NewPoolParams memory retParams) {
        PoolRoleAccounts memory roleAccounts;

        uint64[] memory lambdas = new uint64[](1);
        lambdas[0] = 0.2e18;
        
        int256[][] memory parameters = new int256[][](1);
        parameters[0] = new int256[](1);
        parameters[0][0] = 0.2e18;

        address[][] memory oracles = new address[][](1);
        oracles[0] = new address[](1);
        oracles[0][0] = address(chainlinkOracle);

        uint256[] memory normalizedWeights = new uint256[](tokens.length);
        normalizedWeights[0] = uint256(0.5e18);
        normalizedWeights[1] = uint256(0.5e18);

        IERC20[] memory tokensIERC20 = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokensIERC20[i] = IERC20(tokens[i]);        }
        
        TokenConfig[] memory tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.asIERC20().length; ++i) {
            tokenConfig[i].token = tokens.asIERC20()[i];
            if(rateProviders.length > 0) {
                tokenConfig[i].rateProvider = rateProviders[i];
                tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                    ? TokenType.STANDARD
                    : TokenType.WITH_RATE;
            }
        }

        tokenConfig = sortTokenConfig(tokenConfig);
        
        retParams = QuantAMMWeightedPoolFactory.NewPoolParams(
            "Pool With Donation",
            "PwD",
            tokenConfig,
            normalizedWeights,
            roleAccounts,
            0.02e18,
            address(0),
            true,
            false, // Do not disable unbalanced add/remove liquidity
            0x0000000000000000000000000000000000000000000000000000000000000000,
            [int256(0.5e18),int256(0.5e18)].toMemoryArray(),
            IQuantAMMWeightedPool.PoolSettings(
                tokens.asIERC20(),
                IUpdateRule(new MockMomentumRule(owner)),
                oracles,
                60,
                lambdas,
                0.2e18,
                0.2e18,
                0.3e18,
                parameters,
                address(0)
            ),
            [int256(0.5e18),int256(0.5e18)].toMemoryArray(),
            [int256(0.5e18),int256(0.5e18)].toMemoryArray(),
            3600,
            16,//able to set weights
            new string[][](0)
        );
    }

    function createQuantAMMPool(
        address[] memory tokens,
        string memory label,
        IRateProvider[] memory rateProviders,
        IVaultMock vault,
        address poolCreator
    ) internal returns (address newPoolAddress, bytes memory poolArgsRet) {        
        deployerFactory = address(deployQuantAMMWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        ));
        QuantAMMWeightedPoolFactory.NewPoolParams memory poolCreateSettings = _createPoolParams(tokens, rateProviders);
        (newPoolAddress, poolArgsRet) =  QuantAMMWeightedPoolFactory(deployerFactory).create(poolCreateSettings);
       
        vm.label(newPoolAddress, label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(newPoolAddress, poolCreator);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(newPoolAddress, poolCreator);
    }

    function deployQuantAMMWeightedMathMock() internal returns (QuantAMMWeightedMathMock) {
        if (reusingArtifacts) {
            return
                QuantAMMWeightedMathMock(deployCode(_computeWeightedPathTest(type(QuantAMMWeightedMathMock).name), ""));
        } else {
            return new QuantAMMWeightedMathMock();
        }
    }

    function deployQuantAMMWeightedPoolMock(
        QuantAMMWeightedPool.NewPoolParams memory params,
        IVault vault
    ) internal returns (MockQuantAMMWeightedPool) {
        if (reusingArtifacts) {
            return
                MockQuantAMMWeightedPool(
                    deployCode(_computeWeightedPathTest(type(MockQuantAMMWeightedPool).name), abi.encode(params, vault))
                );
        } else {
            return new MockQuantAMMWeightedPool(params, vault);
        }
    }

    function _computeWeightedPath(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/", name, ".sol/", name, ".json"));
    }

    function _computeWeightedPathTest(string memory name) private view returns (string memory) {
        return string(abi.encodePacked(artifactsRootDir, "contracts/test/", name, ".sol/", name, ".json"));
    }
}
