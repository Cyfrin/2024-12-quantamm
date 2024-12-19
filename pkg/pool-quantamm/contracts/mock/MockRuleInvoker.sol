// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "../rules/UpdateRule.sol";
import "../UpdateWeightRunner.sol";
import "../QuantAMMStorage.sol";

/// @dev Used to test rules in isolation with provided values

contract MockRuleInvoker {
    int256[] weights;

    function getWeights() public view returns (int256[] memory) {
        return weights;
    }

    function invokeRule(
        UpdateRule _rule,
        int256[] calldata prevWeights,
        int256[] calldata data,
        address pool,
        int256[][] calldata parameters,
        uint64[] calldata lambdaStore,
        uint64 epsilonMax,
        uint64 absoluteWeightGuardRail
    ) external {
        weights = _rule.CalculateNewWeights(
            prevWeights,
            data,
            pool,
            parameters,
            lambdaStore,
            epsilonMax,
            absoluteWeightGuardRail
        );
    }
}
