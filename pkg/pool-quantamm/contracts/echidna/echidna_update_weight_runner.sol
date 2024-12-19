// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../rules/base/QuantammMathGuard.sol";

contract EchidnaQuantAMMMathGuard is QuantAMMMathGuard {
    int256[] public weights;

    constructor() {}

    function weight_update_two_tokens(
        uint8 weightDeltaDivisor,
        uint8 epsilonMaxDivisor
    ) public {
        weights = new int256[](2);
        weights[0] = 1e18 / 2;
        weights[1] = 1e18 / 2;
        int256 epsilonMax = int256(uint256(1e18 / epsilonMaxDivisor));
        int256 absoluteWeightChangeGuardRail = int256(uint256(1e18 / epsilonMaxDivisor));
        int256[] memory newWeights = new int256[](2);
        newWeights[0] = weights[0] - int256(uint256(1e18 / weightDeltaDivisor));
        newWeights[1] = weights[1] + int256(uint256(1e18 / weightDeltaDivisor));
        newWeights = _clampWeights(newWeights, absoluteWeightChangeGuardRail);
        newWeights = _normalizeWeightUpdates(weights, newWeights, epsilonMax);
        weights = newWeights;
    }

    function weight_update_multiple_tokens(
        uint8 numWeights,
        uint8 weightDeltaDivisor,
        uint8 epsilonMaxDivisor
    ) public {
        require(numWeights > 1);
        weights = new int256[](numWeights);
        int256 weightSum;
        for (uint i; i < numWeights - 1; ++i) {
            weights[i] = int256(uint256(1e18 / numWeights));
            weightSum += weights[i];
        }
        weights[weights.length - 1] = 1e18 - weightSum;
        int256 epsilonMax = int256(uint256(1e18 / epsilonMaxDivisor));
        int256 absoluteWeightChangeGuardRail = int256(uint256(1e18 / epsilonMaxDivisor));
        int256[] memory newWeights = new int256[](numWeights);
        uint256 numToUpdate = numWeights;
        if (numWeights % 2 == 1) numToUpdate -= 1;
        for (uint i; i < numWeights; ++i) {
            int256 delta = int256(uint256(1e18 / weightDeltaDivisor));
            if (i % 2 == 1) delta = -delta;
            newWeights[i] = weights[i] + delta;
        }
        newWeights = _clampWeights(newWeights, absoluteWeightChangeGuardRail);
        newWeights = _normalizeWeightUpdates(weights, newWeights, epsilonMax);
        weights = newWeights;
    }

    function echidna_check_weights() public view returns (bool) {
        if (weights.length == 0) return true;
        uint256 weightSum;
        bool allPositive = true;
        bool allInBoundaries = true;
        int256 lowerBound = int256((1e18 / 2) * weights.length);
        int256 upperBound = int256(1e18 - lowerBound);
        for (uint i; i < weights.length; ++i) {
            if (weights[i] < 0) allPositive = false;
            if (weights[i] < lowerBound || weights[i] > upperBound)
                allInBoundaries = false;
            weightSum += uint256(weights[i]);
        }
        return allPositive && weightSum == 1e18;
    }
}
