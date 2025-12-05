// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { IV3Router } from "./IV3Router.sol";

/// @title Library for abi decoding in calldata
library V3CalldataDecoder {
    /// @notice equivalent to SliceOutOfBounds.selector, stored in least-significant bits
    uint256 constant SLICE_ERROR_SELECTOR = 0x3b99b53d;

    /// @dev equivalent to: abi.decode(params, (IV3Router.V3ExactInputParams))
    function decodeSwapExactInParams(
        bytes calldata params
    ) internal pure returns (IV3Router.V3ExactInputParams calldata swapParams) {
        // ExactInputParams is a variable length struct so we just have to look up its location
        assembly ("memory-safe") {
            // only safety checks for the minimum length, where path is empty
            // 0x60 = 3 * 0x20 -> 3 elements, path offset, and path length 0
            if lt(params.length, 0x60) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
            swapParams := add(params.offset, calldataload(params.offset))
        }
    }

    /// @dev equivalent to: abi.decode(params, (IV3Router.V3ExactOutputParams))
    function decodeSwapExactOutParams(
        bytes calldata params
    ) internal pure returns (IV3Router.V3ExactOutputParams calldata swapParams) {
        // ExactOutputParams is a variable length struct so we just have to look up its location
        assembly ("memory-safe") {
            // only safety checks for the minimum length, where path is empty
            // 0x60 = 3 * 0x20 -> 3 elements, path offset, and path length 0
            if lt(params.length, 0x60) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
            swapParams := add(params.offset, calldataload(params.offset))
        }
    }
}
