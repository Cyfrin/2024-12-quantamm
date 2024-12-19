// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @notice Generic wrapper around an arbitrary oracle that returns normalized values.
abstract contract OracleWrapper {
    /// @notice Type of the oracle (price, volume, variance, ...). Only price supported for now
    enum OracleType {
        PRICE
    }

    /// @notice Get the data of the underlying oracle, interpretation of data depends on oracle type
    /// @param data The underlying data (can be negative), normalized to 18 decimals
    /// @return data Retrieved oracle data
    /// @return timestamp Last update timestamp
    function getData() public view returns (int216 data, uint40 timestamp) {
        (data, timestamp) = _getData();
        require(timestamp > 0, "INVORCLVAL"); // Sanity check in case oracle returns invalid values
    }

    /// @notice Get data from oracle, to be implemented by child contracts. Needs to return data with 18 decimals
    function _getData() internal view virtual returns (int216 data, uint40 timestamp) {}
}
