// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

interface IV3Router {
    /// @notice Emitted when path has invalid length
    error InvalidPath(uint256 pathLength);

    struct V3ExactInputParams {
        bytes path;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct V3ExactOutputParams {
        bytes path;
        uint256 amountOut;
        uint256 amountInMaximum;
    }
}
