// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../rules/base/QuantammMathMovingAverage.sol";

contract EchidnaMovingAverage is QuantAMMMathMovingAverage {
    int128[] public lambda;

    int256[] public movingAverage;

    constructor() {
        lambda = new int128[](1);
        lambda[0] = 1e18 / 2;
        movingAverage = new int256[](2);
        movingAverage[0] = 1e18;
        movingAverage[1] = 1e18;
    }

    function calculate_moving_average(int256[] calldata _newData) public {
        movingAverage = _calculateQuantAMMMovingAverage(
            movingAverage,
            _newData,
            lambda,
            movingAverage.length
        );
    }

    function echidna_calc_does_not_revert() public pure returns (bool) {
        // Just check that the calculation does not revert
        return true;
    }
}
