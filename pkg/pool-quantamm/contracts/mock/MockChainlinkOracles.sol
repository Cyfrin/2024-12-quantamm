// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import "@balancer-labs/v3-interfaces/contracts/pool-quantamm/OracleWrapper.sol";

contract MockChainlinkOracle is OracleWrapper {
    int216 private fixedReply;
    uint private  immutable delay;
    uint40 public oracleTimestamp;

    constructor(int216 _fixedReply, uint _delay) {
        fixedReply = _fixedReply;
        delay = _delay;
        oracleTimestamp = uint40(block.timestamp);
    }

    function updateData(int216 _fixedReply, uint40 _timestamp) public {
        fixedReply = _fixedReply;
        oracleTimestamp = _timestamp;
    }

    function _getData() internal view override returns (int216 data, uint40 timestamp) {
        data = fixedReply;
        timestamp = uint40(block.timestamp - delay);
    }
}
