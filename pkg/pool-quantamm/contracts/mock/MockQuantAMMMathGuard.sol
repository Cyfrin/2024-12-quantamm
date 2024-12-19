// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.24;

import "../rules/base/QuantammMathGuard.sol";

contract MockQuantAMMMathGuard is QuantAMMMathGuard {
    function mockGuardQuantAMMWeights(
        int256[] memory _weights,
        int256[] calldata _prevWeights,
        int256 _epsilonMax,
        int256 _absoluteWeightGuardRail
    ) external pure returns (int256[] memory guardedNewWeights) {
        guardedNewWeights = _guardQuantAMMWeights(_weights, _prevWeights, _epsilonMax, _absoluteWeightGuardRail);
    }
}
