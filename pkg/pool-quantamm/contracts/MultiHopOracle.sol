// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";

/// @notice For tokens where no direct oracle / price feeds exists, multiple oracle wrappers can be combined to one.
contract MultiHopOracle is OracleWrapper {
    /// @notice Configuration for one hop
    /// @dev Fits in one storage slot
    struct HopConfig {
        OracleWrapper oracle;
        /// @notice Set to true if the result should be inverted, e.g. if we have TOK1/TOK2 but want to multiply by TOK2/TOK1 (i.e., divide by TOK1/TOK2)
        bool invert;
    }

    /// @notice configuration for the oracles
    HopConfig[] public oracles;

    constructor(HopConfig[] memory _oracles) {
        for (uint i = 0; i < _oracles.length; i++) {
            oracles.push(_oracles[i]);
        }
    }

    /// @notice Returns the latest data from one oracle hopping across n oracles
    /// @return data the latest data from the oracle in the QuantAMM format
    /// @return timestamp the timestamp of the data retrieval
    function _getData() internal view override returns (int216 data, uint40 timestamp) {
        HopConfig memory firstOracle = oracles[0];
        (data, timestamp) = firstOracle.oracle.getData();
        if (firstOracle.invert) {
            data = 10 ** 36 / data; // 10^36 (i.e., 1 with 18 decimals * 10^18) to get the inverse with 18 decimals.
            // 10**36 is automatically precomputed by the compiler, no explicit caching needed
        }
        uint256 oracleLength = oracles.length;

        for (uint i = 1; i < oracleLength; ) {
            HopConfig memory oracleConfig = oracles[i];
            (int216 oracleRes, uint40 oracleTimestamp) = oracleConfig.oracle.getData();
            if (oracleTimestamp < timestamp) {
                timestamp = oracleTimestamp; // Return minimum timestamp
            }

            // depends which way the oracle conversion is happening
            if (oracleConfig.invert) {
                data = (data * 10 ** 18) / oracleRes;
            } else {
                data = (data * oracleRes) / 10 ** 18;
            }
            unchecked {
                ++i;
            }
        }
    }
}
