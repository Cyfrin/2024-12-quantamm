// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @param _movingAverage p̅(t)
/// @param _lambda λ
/// @param _numberOfAssets number of assets in the pool
/// @param _pool the target pool address
struct QuantAMMPoolParameters {
    address pool;
    uint numberOfAssets;
    int128[] lambda;
    int256[] movingAverage;
}
