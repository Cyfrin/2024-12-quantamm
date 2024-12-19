// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../QuantAMMStorage.sol";

contract EchidnaStoragePack is
    ScalarQuantAMMBaseStorage,
    ScalarRuleQuantAMMStorage,
    VectorRuleQuantAMMStorage
{
    int256[] internal mockQuantAMMMatrix;
    int256[][] internal matrixResult;

    function r_packUnpack32Array(int256[] memory sourceArray) external pure {
        require(sourceArray.length % 8 == 0);
        for (uint256 i; i < sourceArray.length; i++) {
            sourceArray[i] = sourceArray[i] * 1e9;
        }
        uint256 len = sourceArray.length;
        int256[] memory targetArray = quantAMMPack32Array(sourceArray);
        int256[] memory initial = quantAMMUnpack32Array(targetArray, len);
        for (uint256 i; i < sourceArray.length; i++) {
            assert(sourceArray[i] == initial[i]);
        }
    }

    function r_packUnpack128Array(int256[] memory sourceArray) external pure {
        require(sourceArray.length % 2 == 0);
        uint256 len = sourceArray.length;
        int256[] memory targetArray = _quantAMMPack128Array(sourceArray);
        int256[] memory initial = _quantAMMUnpack128Array(targetArray, len);
        for (uint256 i; i < sourceArray.length; i++) {
            assert(sourceArray[i] == initial[i]);
        }
    }

    function r_packUnpack128Matrix(int256[][] memory sourceMatrix) external {
        uint storageLength;
        if ((sourceMatrix.length * sourceMatrix.length) % 2 == 0) {
            storageLength = (sourceMatrix.length * sourceMatrix.length) / 2;
        } else {
            storageLength =
                ((sourceMatrix.length * sourceMatrix.length) - 1) /
                2;
            ++storageLength;
        }
        require(sourceMatrix.length >= 2);
        for (uint256 i = 0; i < sourceMatrix.length; i++) {
            require(sourceMatrix[i].length >= 2);
        }
        for (uint256 i = 0; i < sourceMatrix.length; i++) {
            for (uint256 j = 0; j < sourceMatrix[i].length; j++) {
                require(sourceMatrix[i][j] < type(int32).max);
            }
        }

        mockQuantAMMMatrix = new int256[](storageLength);
        _quantAMMPack128Matrix(sourceMatrix, mockQuantAMMMatrix);
        matrixResult = _quantAMMUnpack128Matrix(mockQuantAMMMatrix, sourceMatrix.length);

        for (uint256 i = 0; i < sourceMatrix.length; i++) {
            for (uint256 j = 0; j < sourceMatrix[i].length; j++) {
                require(sourceMatrix[i][j] < type(int32).max);
                assert(sourceMatrix[i][j] == matrixResult[i][j]);
            }
        }
    }
}
