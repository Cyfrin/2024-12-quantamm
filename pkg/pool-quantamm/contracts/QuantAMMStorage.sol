// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import "@prb/math/contracts/PRBMathSD59x18.sol";

/*
ARCHITECTURE DESIGN NOTES

The storage is a generalised AMM that can be used for any asset type, including scalars, vectors and matrices.
The storage is designed to be as gas efficient as possible, and to be as flexible as possible.
The storage is designed to be used with the QuantAMM contract, but can be used with any contract that implements the QuantAMM interface.
A couple of assumptions underpin the design: 

- 1 that you can pack only the same type of int.
- 2 that with the matrices calculations are only done on square matrices.
- 3 All checks regarding array lengths are done on registration of the pool and are fixed.

 */

// On casting to uint first, Solidity does not revert when casting negative values
//it just interprets the bitstring as a uint.
//Normally this is unintended behaviour, but here it is actually useful

/// @title QuantAMMStorage contract for QuantAMM storage slot packing and unpacking
/// @notice Contains the logic for packing and unpacking storage slots with 128 bit integers
abstract contract QuantAMMStorage {
    //for gas efficiency, likely compiler does this anyway
    int256 private constant MAX128 = int256(type(int128).max);
    int256 private constant MIN128 = int256(type(int128).min);

    /// @notice Packs two 128 bit integers into one 256 bit integer
    /// @param _leftInt the left integer to pack
    /// @param _rightInt the right integer to pack
    function _quantAMMPackTwo128(int256 _leftInt, int256 _rightInt) internal pure returns (int256 packed) {
        require((_leftInt <= MAX128) && (_rightInt <= MAX128), "Overflow");
        require((_leftInt >= MIN128) && (_rightInt >= MIN128), "Underflow");
        packed = (_leftInt << 128) | int256(uint256(_rightInt << 128) >> 128);
    }
}

/// @title QuantAMMStorage contract for QuantAMM storage slot packing and unpacking scalar quantAMM Base weights
/// @notice Contains the logic for packing and unpacking storage slots with 32 bit integers
abstract contract ScalarQuantAMMBaseStorage {
    //for gas efficiency, likely compiler does this anyway
    int256 private constant MAX32 = int256(type(int32).max);
    int256 private constant MIN32 = int256(type(int32).min);

    /// @notice Packs eight 32 bit integers into one 256 bit integer
    /// @param _firstInt the first integer to pack
    /// @param _secondInt the second integer to pack
    /// @param _thirdInt the third integer to pack
    /// @param _fourthInt the fourth integer to pack
    /// @param _fifthInt the fifth integer to pack
    /// @param _sixthInt the sixth integer to pack
    /// @param _seventhInt the seventh integer to pack
    /// @param _eighthInt the eighth integer to pack
    function quantAMMPackEight32(
        int256 _firstInt,
        int256 _secondInt,
        int256 _thirdInt,
        int256 _fourthInt,
        int256 _fifthInt,
        int256 _sixthInt,
        int256 _seventhInt,
        int256 _eighthInt
    ) internal pure returns (int256 packed) {
        require(
            _firstInt <= MAX32 &&
                _firstInt >= MIN32 &&
                _secondInt <= MAX32 &&
                _secondInt >= MIN32 &&
                _thirdInt <= MAX32 &&
                _thirdInt >= MIN32 &&
                _fourthInt <= MAX32 &&
                _fourthInt >= MIN32 &&
                _fifthInt <= MAX32 &&
                _fifthInt >= MIN32 &&
                _sixthInt <= MAX32 &&
                _sixthInt >= MIN32 &&
                _seventhInt <= MAX32 &&
                _seventhInt >= MIN32 &&
                _eighthInt <= MAX32 &&
                _eighthInt >= MIN32,
            "Overflow"
        );

        int256 firstPacked = int256(uint256(_firstInt << 224) >> 224) << 224;
        int256 secondPacked = int256(uint256(_secondInt << 224) >> 224) << 192;
        int256 thirdPacked = int256(uint256(_thirdInt << 224) >> 224) << 160;
        int256 fourthPacked = int256(uint256(_fourthInt << 224) >> 224) << 128;
        int256 fifthPacked = int256(uint256(_fifthInt << 224) >> 224) << 96;
        int256 sixthPacked = int256(uint256(_sixthInt << 224) >> 224) << 64;
        int256 seventhPacked = int256(uint256(_seventhInt << 224) >> 224) << 32;
        int256 eighthPacked = int256(uint256(_eighthInt << 224) >> 224);

        packed =
            firstPacked |
            secondPacked |
            thirdPacked |
            fourthPacked |
            fifthPacked |
            sixthPacked |
            seventhPacked |
            eighthPacked;
    }

    /// @notice Unpacks a 256 bit integer into 8 32 bit integers
    /// @param sourceElem the integer to unpack
    function quantAMMUnpack32(int256 sourceElem) internal pure returns (int256[] memory targetArray) {
        targetArray = new int256[](8);
        targetArray[0] = (sourceElem >> 224) * 1e9;
        targetArray[1] = int256(int32(sourceElem >> 192)) * 1e9;
        targetArray[2] = int256(int32(sourceElem >> 160)) * 1e9;
        targetArray[3] = int256(int32(sourceElem >> 128)) * 1e9;
        targetArray[4] = int256(int32(sourceElem >> 96)) * 1e9;
        targetArray[5] = int256(int32(sourceElem >> 64)) * 1e9;
        targetArray[6] = int256(int32(sourceElem >> 32)) * 1e9;
        targetArray[7] = int256(int32(sourceElem)) * 1e9;

        return targetArray;
    }

    /// @notice Unpacks a 256 bit integer into n 32 bit integers
    /// @param _sourceArray the array to unpack
    /// @param _targetArrayLength the number of 32 bit integers to unpack
    function quantAMMUnpack32Array(
        int256[] memory _sourceArray,
        uint _targetArrayLength
    ) internal pure returns (int256[] memory targetArray) {
        require(_sourceArray.length * 8 >= _targetArrayLength, "SRC!=TGT");
        targetArray = new int256[](_targetArrayLength);
        uint targetIndex;
        uint sourceArrayLengthMinusOne = _sourceArray.length - 1;
        bool divisibleByEight = _targetArrayLength % 8 == 0;
        uint stickyEndSourceElem;

        //more than the first slot so need to loop
        if (_targetArrayLength > 8) {
            for (uint i; i < _sourceArray.length; ) {
                if (divisibleByEight || i < sourceArrayLengthMinusOne) {
                    unchecked {
                        int256 sourceElem = _sourceArray[i];
                        targetArray[targetIndex] = (sourceElem >> 224) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem >> 192)) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem >> 160)) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem >> 128)) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem >> 96)) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem >> 64)) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem >> 32)) * 1e9;
                        ++targetIndex;

                        targetArray[targetIndex] = int256(int32(sourceElem)) * 1e9;
                        ++targetIndex;
                    }
                }
                unchecked {
                    ++i;
                }
            }
            //get sticky end slot
            if (!divisibleByEight) {
                unchecked {
                    stickyEndSourceElem = _sourceArray.length - 1;
                }
            }
        } else if (_targetArrayLength == 8) {
            //effiency at the price of increased function length works out cheaper
            //hardcoded index access is cheaper than a loop
            int256 sourceElem = _sourceArray[0];
            targetArray[0] = (sourceElem >> 224) * 1e9;
            targetArray[1] = int256(int32(sourceElem >> 192)) * 1e9;
            targetArray[2] = int256(int32(sourceElem >> 160)) * 1e9;
            targetArray[3] = int256(int32(sourceElem >> 128)) * 1e9;
            targetArray[4] = int256(int32(sourceElem >> 96)) * 1e9;
            targetArray[5] = int256(int32(sourceElem >> 64)) * 1e9;
            targetArray[6] = int256(int32(sourceElem >> 32)) * 1e9;
            targetArray[7] = int256(int32(sourceElem)) * 1e9;
        }

        // deal with up to 7 sticky end elements
        if (!divisibleByEight) {
            unchecked {
                uint offset = 224;
                for (uint i = targetIndex; i < targetArray.length; ) {
                    targetArray[i] = int256(int32(_sourceArray[stickyEndSourceElem] >> offset)) * 1e9;
                    offset -= 32;
                    ++i;
                }
            }
        }
    }

    /// @notice Packs an array of 32 bit integers into an array of 256 bit integers
    /// @param _sourceArray the array to pack
    function quantAMMPack32Array(int256[] memory _sourceArray) internal pure returns (int256[] memory targetArray) {
        uint targetArrayLength;
        uint storageIndex;
        uint nonStickySourceLength;

        //logic if more than 1 slot is required to store the array
        if (_sourceArray.length >= 8) {
            for (uint i = _sourceArray.length; i >= 8; ) {
                unchecked {
                    if (i % 8 == 0) {
                        nonStickySourceLength = i;
                        break;
                    }
                    --i;
                }
            }

            //add one for the sticky end to be dealt with later
            if (_sourceArray.length != nonStickySourceLength) {
                unchecked {
                    targetArrayLength = (nonStickySourceLength / 8) + 1;
                }
            } else {
                unchecked {
                    targetArrayLength = (nonStickySourceLength) / 8;
                }
            }

            targetArray = new int256[](targetArrayLength);

            for (uint i; i < nonStickySourceLength; ) {
                unchecked {
                    targetArray[storageIndex] = quantAMMPackEight32(
                        int256(_sourceArray[i] / 1e9),
                        int256(_sourceArray[i + 1] / 1e9),
                        int256(_sourceArray[i + 2] / 1e9),
                        int256(_sourceArray[i + 3] / 1e9),
                        int256(_sourceArray[i + 4] / 1e9),
                        int256(_sourceArray[i + 5] / 1e9),
                        int256(_sourceArray[i + 6] / 1e9),
                        int256(_sourceArray[i + 7] / 1e9)
                    );

                    i += 8;
                    ++storageIndex;
                }
            }
        }

        if (targetArrayLength == 0) {
            unchecked {
                if (_sourceArray.length <= 8) {
                    targetArrayLength = 1;
                } else {
                    targetArrayLength = (nonStickySourceLength / 8) + 1;
                }

                targetArray = new int256[](targetArrayLength);
            }
        }
        //pack up to 7 sticky ends
        uint stickyEndElems = _sourceArray.length - nonStickySourceLength;
        if (stickyEndElems > 0) {
            uint offset = 224;
            int256 packed;
            for (uint i = nonStickySourceLength; i < _sourceArray.length; ) {
                unchecked {
                    int256 elem = _sourceArray[i] / 1e9;
                    require(elem <= MAX32 && elem >= MIN32, "Overflow");
                    packed |= int256(uint256(elem << 224) >> 224) << offset;
                    offset -= 32;
                    ++i;
                }
            }
            targetArray[storageIndex] = packed;
        }
    }
}

/// @title QuantAMMStorage contract for QuantAMM storage slot packing and unpacking scalar rule weights
/// @notice Contains the logic for packing and unpacking storage slots with 128 bit integers for rule weights
abstract contract ScalarRuleQuantAMMStorage is QuantAMMStorage {
    /// @notice Packs n 128 bit integers into n/2 256 bit integers
    /// @param _sourceArray the array to pack
    function _quantAMMPack128Array(int256[] memory _sourceArray) internal pure returns (int256[] memory targetArray) {
        uint sourceArrayLength = _sourceArray.length;
        uint targetArrayLength = sourceArrayLength;
        uint storageIndex;

        require(_sourceArray.length != 0, "LEN0");

        if (_sourceArray.length % 2 == 0) {
            unchecked {
                targetArrayLength = (targetArrayLength) / 2;
            }
            targetArray = new int256[](targetArrayLength);
            for (uint i; i < sourceArrayLength - 1; ) {
                targetArray[storageIndex] = _quantAMMPackTwo128(_sourceArray[i], _sourceArray[i + 1]);
                unchecked {
                    i += 2;
                    ++storageIndex;
                }
            }
        } else {
            int256 lastArrayItem = _sourceArray[_sourceArray.length - 1];
            require(
                (lastArrayItem >= int256(type(int128).min)) && (lastArrayItem <= int256(type(int128).max)),
                "Last array element overflow"
            );
            unchecked {
                targetArrayLength = ((targetArrayLength - 1) / 2) + 1;
            }
            targetArray = new int256[](targetArrayLength);
            uint sourceArrayLengthMinusTwo = sourceArrayLength - 2;
            for (uint i; i < sourceArrayLengthMinusTwo; ) {
                targetArray[storageIndex] = _quantAMMPackTwo128(_sourceArray[i], _sourceArray[i + 1]);
                unchecked {
                    i += 2;
                    ++storageIndex;
                }
            }
            targetArray[storageIndex] = int256(int128(_sourceArray[sourceArrayLength - 1]));
        }
    }

    /// @notice Unpacks n/2 256 bit integers into n 128 bit integers
    /// @param _sourceArray the array to unpack
    /// @param _targetArrayLength the number of 128 bit integers to unpack
    function _quantAMMUnpack128Array(
        int256[] memory _sourceArray,
        uint _targetArrayLength
    ) internal pure returns (int256[] memory targetArray) {
        require(_sourceArray.length * 2 >= _targetArrayLength, "SRC!=TGT");
        targetArray = new int256[](_targetArrayLength);
        uint targetIndex;
        uint sourceArrayLengthMinusOne = _sourceArray.length - 1;
        bool divisibleByTwo = _targetArrayLength % 2 == 0;
        for (uint i; i < _sourceArray.length; ) {
            targetArray[targetIndex] = _sourceArray[i] >> 128;
            unchecked {
                ++targetIndex;
            }
            if ((!divisibleByTwo && i < sourceArrayLengthMinusOne) || divisibleByTwo) {
                targetArray[targetIndex] = int256(int128(_sourceArray[i]));
            }
            unchecked {
                ++i;
                ++targetIndex;
            }
        }

        if (!divisibleByTwo) {
            targetArray[_targetArrayLength - 1] = int256(int128(_sourceArray[sourceArrayLengthMinusOne]));
        }
    }
}

// On casting to uint first, Solidity does not revert when casting negative values
//it just interprets the bitstring as a uint.
//Normally this is unintended behaviour, but here it is actually useful
/// @title QuantAMMStorage contract for QuantAMM storage slot packing and unpacking vector rule weights
/// @notice This logic to pack and unpack vectors is hardcoded for square matrices only as that is the usecase for QuantAMM
abstract contract VectorRuleQuantAMMStorage is QuantAMMStorage {
    /// @notice Packs n 128 bit integers into n/2 256 bit integers
    /// @param _sourceMatrix the matrix to pack
    /// @param _targetArray the array to pack into
    function _quantAMMPack128Matrix(int256[][] memory _sourceMatrix, int256[] storage _targetArray) internal {
        // 2d array of 3 elements each with 3 elements

        // | |1|, |2|, |3|, |
        // | |4|, |5|, |6|, |
        // | |7|, |8|, |9|  |

        // becomes array of 5 elements, the last being half filled

        // | 1 2 | 3 4 | 5 6 | 7 8 | 9 _ |

        // this saves 3 length SSTORES and SLOADS, as well as reducing the slots by 3

        uint targetArrayLength = _targetArray.length;
        require(targetArrayLength * 2 >= _sourceMatrix.length * _sourceMatrix.length, "Matrix doesnt fit storage");
        uint targetArrayIndex;
        int256 leftInt;
        uint right;
        unchecked {
            for (uint i; i < _sourceMatrix.length; ) {
                for (uint j; j < _sourceMatrix[i].length; ) {
                    require(
                        (_sourceMatrix[i][j] <= int256(type(int128).max)) &&
                            (_sourceMatrix[i][j] >= int256(type(int128).min)),
                        "Over/Under-flow"
                    );
                    if (right == 1) {
                        right = 0;
                        //SSTORE done inline to avoid length SSTORE as length doesnt ever change
                        _targetArray[targetArrayIndex] =
                            (leftInt << 128) |
                            int256(uint256(_sourceMatrix[i][j] << 128) >> 128);
                        ++targetArrayIndex;
                    } else {
                        leftInt = _sourceMatrix[i][j];
                        right = 1;
                    }
                    ++j;
                }
                ++i;
            }
            if (((_sourceMatrix.length * _sourceMatrix.length) % 2) != 0) {
                _targetArray[targetArrayLength - 1] = int256(
                    int128(_sourceMatrix[_sourceMatrix.length - 1][_sourceMatrix.length - 1])
                );
            }
        }
    }

    /// @notice Unpacks packed array into a 2d array of 128 bit integers
    /// @param _sourceArray the array to unpack
    /// @param _numberOfAssets the number of 128 bit integers to unpack
    function _quantAMMUnpack128Matrix(
        int256[] memory _sourceArray,
        uint _numberOfAssets
    ) internal pure returns (int256[][] memory targetArray) {
        // | 1 2 | 3 4 | 5 6 | 7 8 | 9 _ |

        // becomes 2d array of 3 elements each with 3 elements

        // | |1|, |2|, |3|, |
        // | |4|, |5|, |6|, |
        // | |7|, |8|, |9|  |
        require(_sourceArray.length * 2 >= _numberOfAssets * _numberOfAssets, "Source cannot provide target");
        targetArray = new int256[][](_numberOfAssets);
        for (uint i; i < _numberOfAssets; ) {
            targetArray[i] = new int256[](_numberOfAssets);
            unchecked {
                ++i;
            }
        }

        uint targetIndex;
        uint targetRow;
        for (uint i; i < _sourceArray.length; ) {
            if (targetIndex < _numberOfAssets) {
                targetArray[targetRow][targetIndex] = int256(int128(_sourceArray[i] >> 128));
                unchecked {
                    ++targetIndex;
                }

                if (targetIndex < _numberOfAssets) {
                    targetArray[targetRow][targetIndex] = int256(int128(_sourceArray[i]));
                    unchecked {
                        ++targetIndex;
                    }
                } else {
                    unchecked {
                        ++targetRow;
                        targetIndex = 0;
                    }
                    if (targetRow < _numberOfAssets) {
                        targetArray[targetRow] = new int256[](_numberOfAssets);
                        if (targetIndex < _numberOfAssets) {
                            targetArray[targetRow][targetIndex] = int256(int128(_sourceArray[i]));
                            unchecked {
                                ++targetIndex;
                            }
                        }
                    }
                }
            } else {
                unchecked {
                    ++targetRow;
                    targetIndex = 0;
                }
                if (targetRow < _numberOfAssets) {
                    targetArray[targetRow] = new int256[](_numberOfAssets);
                    targetArray[targetRow][targetIndex] = int256(int128(_sourceArray[i] >> 128));
                    unchecked {
                        ++targetIndex;
                    }

                    if (targetIndex < _numberOfAssets) {
                        targetArray[targetRow][targetIndex] = int256(int128(_sourceArray[i]));
                        unchecked {
                            ++targetIndex;
                        }
                    } else {
                        unchecked {
                            ++targetRow;
                            targetIndex = 0;
                        }
                        if (targetRow < _numberOfAssets) {
                            targetArray[targetRow] = new int256[](_numberOfAssets);
                        }
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        if ((_numberOfAssets * _numberOfAssets) % 2 != 0) {
            targetArray[_numberOfAssets - 1][_numberOfAssets - 1] = int256(
                int128(_sourceArray[_sourceArray.length - 1])
            );
        }
    }
}
