// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;
import "../QuantAMMStorage.sol";

contract MockQuantAMMStorage is ScalarRuleQuantAMMStorage, ScalarQuantAMMBaseStorage, VectorRuleQuantAMMStorage {
    int256[] public mockQuantAMMMatrix;
    int256[][] public matrixResult;

    function ExternalEncode(int256 leftInt, int256 rightInt) external pure returns (int256 result) {
        result = _quantAMMPackTwo128(leftInt, rightInt);
    }

    function ExternalEncode(int64 leftInt, int128 rightInt) external pure returns (int256 result) {
        result = _quantAMMPackTwo128(leftInt, rightInt);
    }

    function ExternalEncodeArray(int256[] memory sourceArray) external pure returns (int256[] memory result) {
        result = _quantAMMPack128Array(sourceArray);
    }
    
    function ExternalQuantAMMPack32Array(int256[] memory sourceArray) external pure returns (int256[] memory result) {
        result = quantAMMPack32Array(sourceArray);
    }
    
    function ExternalEncodeDecode128Array(
        int256[] memory sourceArray,
        uint targetLength
    ) external pure returns (int256[] memory result) {
        int256[] memory result1 = _quantAMMPack128Array(sourceArray);
        int256[] memory result2 = _quantAMMUnpack128Array(result1, targetLength);

        result = result2;
    }

    function ExternalEncodeDecode32Array(
        int256[] memory sourceArray,
        uint targetLength
    ) external pure returns (int256[] memory result) {
        int256[] memory result1 = quantAMMPack32Array(sourceArray);
        int256[] memory result2 = quantAMMUnpack32Array(result1, targetLength);
        result = result2;
    }

    function ExternalEncodeDecodeMatrix(int256[][] memory sourceMatrix) external {
        uint storageLength;
        if ((sourceMatrix.length * sourceMatrix.length) % 2 == 0) {
            storageLength = (sourceMatrix.length * sourceMatrix.length) / 2;
        } else {
            storageLength = ((sourceMatrix.length * sourceMatrix.length) - 1) / 2;
            ++storageLength;
        }
        mockQuantAMMMatrix = new int256[](storageLength);
        _quantAMMPack128Matrix(sourceMatrix, mockQuantAMMMatrix);
        matrixResult = _quantAMMUnpack128Matrix(mockQuantAMMMatrix, sourceMatrix.length);
    }

    function GetMatrixResult() external view returns (int256[][] memory) {
        return matrixResult;
    }

    function ExternalSingleEncode(int256 leftInt, int256 rightInt) external pure returns (int256 result) {
        result = _quantAMMPackTwo128(leftInt, rightInt);
    }

    function ExternalDecode128(
        int256[] memory sourceArray,
        uint resultArrayLength
    ) external pure returns (int256[] memory resultArray) {
        resultArray = _quantAMMUnpack128Array(sourceArray, resultArrayLength);
    }

    function ExternalSingleDecode(int256 leftInt) external pure returns (int256 result) {
        result = leftInt;
    }
}
