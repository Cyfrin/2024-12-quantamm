// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";

abstract contract QuantAMMTestUtils is Test{
    
    
    int256 internal SCALE18 = 1e18;
    /// @dev The maximum value a signed 59.18-decimal fixed-point number can have.
    int256 internal MAX_SD59x18 =
        57896044618658097711785492504343953926634992332820282019728_792003956564819967;

    /// @dev The minimum value a signed 59.18-decimal fixed-point number can have.
    int256 internal MIN_SD59x18 =
        -57896044618658097711785492504343953926634992332820282019728_792003956564819968;

    function maxScaledFixedPoint18() internal view returns (int256){
        return MAX_SD59x18 / SCALE18;
    }
    
    function minScaledFixedPoint18() internal view returns (int256){
        return MIN_SD59x18 / SCALE18;
    }


    function checkResult(int256[] memory res, int256[] memory expectedRes) internal pure {
        for (uint256 i = 0; i < expectedRes.length; i++) {
            assertEq(expectedRes[i], res[i]); 
        }
    }

    function checkMatrixResult(int256[][] memory redecoded, int256[][] memory targetMatrix) internal pure {
        for (uint256 i = 0; i < targetMatrix.length; i++) {
            for (uint256 j = 0; j < targetMatrix[i].length; j++) {
                assertEq(redecoded[i][j], targetMatrix[i][j]);
            }
        }
    }

    function convert2DArrayToDynamic(int256[4][4] memory arr) internal pure returns (int256[][] memory) {
        int256[][] memory res = new int256[][](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            res[i] = new int256[](arr[i].length);
            for (uint256 j = 0; j < arr[i].length; j++) {
                res[i][j] = arr[i][j];
            }
        }
        return res;
    }
    function convert2DArrayToDynamic(int256[2][4] memory arr) internal pure returns (int256[][] memory) {
        int256[][] memory res = new int256[][](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            res[i] = new int256[](arr[i].length);
            for (uint256 j = 0; j < arr[i].length; j++) {
                res[i][j] = arr[i][j];
            }
        }
        return res;
    }

    function convert2DArrayToDynamic(int256[3][5] memory arr) internal pure returns (int256[][] memory) {
        int256[][] memory res = new int256[][](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            res[i] = new int256[](arr[i].length);
            for (uint256 j = 0; j < arr[i].length; j++) {
                res[i][j] = arr[i][j];
            }
        }
        return res;
    }

    function covert3DArrayToDynamic(int256[2][2][4] memory arr) internal pure returns (int256[][][] memory) {
        int256[][][] memory res = new int256[][][](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            res[i] = new int256[][](arr[i].length);
            for (uint256 j = 0; j < arr[i].length; j++) {
                res[i][j] = new int256[](arr[i][j].length);
                for (uint256 k = 0; k < arr[i][j].length; k++) {
                    res[i][j][k] = arr[i][j][k];
                }
            }
        }
        return res;
    }

}

