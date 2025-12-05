// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";

import { PathKey } from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import { CalldataDecoder } from "@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { DeltaResolver } from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { ActionConstants } from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

uint128 constant SWAP_CONTRACT_BALANCE = type(uint128).max;

/// @title UniswapV4Router
/// @notice Abstract contract that contains all internal logic needed for routing through Uniswap v4 pools
/// @dev the entry point to executing actions in this contract is calling `BaseActionsRouter._executeActions`
/// An inheriting contract should call _executeActions at the point that they wish actions to be executed
abstract contract UniswapV4Actions is IV4Router, DeltaResolver {
    using SafeCast for *;

    uint256 private constant PRECISION = 1e18;

    function _swapExactInputSingle(IV4Router.ExactInputSingleParams calldata params) internal {
        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn = _getFullCredit(
                params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1
            ).toUint128();
        } else if (amountIn == SWAP_CONTRACT_BALANCE) {
            amountIn = (params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1)
                .balanceOfSelf()
                .toUint128();
        }
        uint128 amountOut = _swap(
            params.poolKey,
            params.zeroForOne,
            -int256(uint256(amountIn)),
            params.hookData
        ).toUint128();
        if (amountOut < params.amountOutMinimum)
            revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
    }

    function _swapExactInput(IV4Router.ExactInputParams calldata params) internal {
        unchecked {
            // Caching for gas savings
            uint256 pathLength = params.path.length;
            uint128 amountOut;
            Currency currencyIn = params.currencyIn;
            uint128 amountIn = params.amountIn;
            if (amountIn == SWAP_CONTRACT_BALANCE) {
                amountIn = currencyIn.balanceOfSelf().toUint128();
            } else if (amountIn == ActionConstants.OPEN_DELTA) {
                amountIn = _getFullCredit(currencyIn).toUint128();
            }
            PathKey calldata pathKey;

            uint256 perHopSlippageLength = params.maxHopSlippage.length;
            if (perHopSlippageLength != 0 && perHopSlippageLength != pathLength)
                revert InvalidHopSlippageLength();

            for (uint256 i = 0; i < pathLength; i++) {
                pathKey = params.path[i];
                (PoolKey memory poolKey, bool zeroForOne) = pathKey.getPoolAndSwapDirection(
                    currencyIn
                );
                // The output delta will always be positive, except for when interacting with certain hook pools
                amountOut = _swap(poolKey, zeroForOne, -int256(uint256(amountIn)), pathKey.hookData)
                    .toUint128();

                if (perHopSlippageLength != 0) {
                    uint256 price = (amountIn * PRECISION) / amountOut;
                    uint256 maxSlippage = params.maxHopSlippage[i];
                    if (price > maxSlippage)
                        revert V4TooLittleReceivedPerHop(i, maxSlippage, price);
                }

                amountIn = amountOut;
                currencyIn = pathKey.intermediateCurrency;
            }

            if (amountOut < params.amountOutMinimum)
                revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
        }
    }

    function _swapExactOutputSingle(IV4Router.ExactOutputSingleParams calldata params) internal {
        uint128 amountOut = params.amountOut;
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut = _getFullDebt(
                params.zeroForOne ? params.poolKey.currency1 : params.poolKey.currency0
            ).toUint128();
        } else if (amountOut == SWAP_CONTRACT_BALANCE) {
            amountOut = (params.zeroForOne ? params.poolKey.currency1 : params.poolKey.currency0)
                .balanceOfSelf()
                .toUint128();
        }
        uint128 amountIn = (
            uint256(
                -int256(
                    _swap(
                        params.poolKey,
                        params.zeroForOne,
                        int256(uint256(amountOut)),
                        params.hookData
                    )
                )
            )
        ).toUint128();
        if (amountIn > params.amountInMaximum)
            revert V4TooMuchRequested(params.amountInMaximum, amountIn);
    }

    function _swapExactOutput(IV4Router.ExactOutputParams calldata params) internal {
        unchecked {
            // Caching for gas savings
            uint256 pathLength = params.path.length;
            uint128 amountIn;
            uint128 amountOut = params.amountOut;
            Currency currencyOut = params.currencyOut;
            PathKey calldata pathKey;

            if (amountOut == ActionConstants.OPEN_DELTA) {
                amountOut = _getFullDebt(currencyOut).toUint128();
            } else if (amountOut == SWAP_CONTRACT_BALANCE) {
                amountOut = currencyOut.balanceOfSelf().toUint128();
            }

            uint256 perHopSlippageLength = params.maxHopSlippage.length;
            if (perHopSlippageLength != 0 && perHopSlippageLength != pathLength)
                revert InvalidHopSlippageLength();

            for (uint256 i = pathLength; i > 0; i--) {
                pathKey = params.path[i - 1];
                (PoolKey memory poolKey, bool oneForZero) = pathKey.getPoolAndSwapDirection(
                    currencyOut
                );
                // The output delta will always be negative, except for when interacting with certain hook pools
                amountIn = (
                    uint256(
                        -int256(
                            _swap(
                                poolKey,
                                !oneForZero,
                                int256(uint256(amountOut)),
                                pathKey.hookData
                            )
                        )
                    )
                ).toUint128();

                if (perHopSlippageLength != 0) {
                    uint256 price = (amountIn * PRECISION) / amountOut;
                    uint256 maxSlippage = params.maxHopSlippage[i - 1];
                    if (price > maxSlippage)
                        revert V4TooMuchRequestedPerHop(i - 1, maxSlippage, price);
                }
                amountOut = amountIn;
                currencyOut = pathKey.intermediateCurrency;
            }
            if (amountIn > params.amountInMaximum)
                revert V4TooMuchRequested(params.amountInMaximum, amountIn);
        }
    }

    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata hookData
    ) private returns (int128 reciprocalAmount) {
        // for protection of exactOut swaps, sqrtPriceLimit is not exposed as a feature in this contract
        unchecked {
            BalanceDelta delta = poolManager.swap(
                poolKey,
                SwapParams(
                    zeroForOne,
                    amountSpecified,
                    zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                ),
                hookData
            );

            reciprocalAmount = (zeroForOne == amountSpecified < 0)
                ? delta.amount1()
                : delta.amount0();
        }
    }
}
