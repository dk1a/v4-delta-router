// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Currency } from "@uniswap/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { SafeCast } from "@uniswap/v4-periphery/lib/v4-core/src/libraries/SafeCast.sol";
import { DeltaResolver } from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import { ActionConstants } from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";

import { IAerodromeSwapRouter, IAerodromeQuoter } from "./AerodromeInterfaces.sol";
import { IV3Router } from "../v3/IV3Router.sol";

import { console } from "forge-std/console.sol";

abstract contract AerodromeActions is IV3Router, DeltaResolver {
    using SafeCast for uint256;

    IAerodromeSwapRouter public immutable aerodromeRouter;

    constructor(address _aerodromeRouter) {
        aerodromeRouter = IAerodromeSwapRouter(_aerodromeRouter);
    }

    function _verifyPathLength(uint256 pathLength) private pure {
        if (pathLength < 43 || (pathLength - 20) % 23 != 0) {
            revert IV3Router.InvalidPath(pathLength);
        }
    }

    function _aerodromeSwapExactInput(
        IV3Router.V3ExactInputParams calldata params
    ) internal returns (uint128) {
        _verifyPathLength(params.path.length);
        Currency tokenIn = Currency.wrap(address(bytes20(params.path)));

        uint256 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn = _getFullCredit(tokenIn).toUint128();
        } else if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = tokenIn.balanceOfSelf().toUint128();
        }

        IERC20(Currency.unwrap(tokenIn)).approve(address(aerodromeRouter), amountIn * 2);

        console.log("asdasd");
        console.log(amountIn);

        uint256 amountOut = aerodromeRouter.exactInput(
            IAerodromeSwapRouter.ExactInputParams({
                path: params.path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: params.amountOutMinimum
            })
        );
        return uint128(amountOut);
    }

    function _aerodromeSwapExactOutput(
        IV3Router.V3ExactOutputParams calldata params
    ) internal returns (uint128) {
        _verifyPathLength(params.path.length);
        Currency tokenIn = Currency.wrap(address(bytes20(params.path[23:43])));
        Currency tokenOut = Currency.wrap(address(bytes20(params.path)));

        uint256 amountOut = params.amountOut;
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut = _getFullDebt(tokenOut).toUint128();
        } else if (amountOut == ActionConstants.CONTRACT_BALANCE) {
            amountOut = tokenOut.balanceOfSelf().toUint128();
        }

        IERC20(Currency.unwrap(tokenIn)).approve(address(aerodromeRouter), params.amountInMaximum);

        uint256 amountIn = aerodromeRouter.exactOutput(
            IAerodromeSwapRouter.ExactOutputParams({
                path: params.path,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: params.amountInMaximum
            })
        );
        return uint128(amountIn);
    }

    function _aerodromeSwapExactInputSingle(
        Currency tokenIn,
        Currency tokenOut,
        int24 tickSpacing,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint128) {
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn = _getFullCredit(tokenIn).toUint128();
        } else if (amountIn == ActionConstants.CONTRACT_BALANCE) {
            amountIn = tokenIn.balanceOfSelf().toUint128();
        }

        IERC20(Currency.unwrap(tokenIn)).approve(address(aerodromeRouter), amountIn);

        uint256 amountOut = aerodromeRouter.exactInputSingle(
            IAerodromeSwapRouter.ExactInputSingleParams({
                tokenIn: Currency.unwrap(tokenIn),
                tokenOut: Currency.unwrap(tokenOut),
                tickSpacing: tickSpacing,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
        return uint128(amountOut);
    }

    function _aerodromeSwapExactOutputSingle(
        Currency tokenIn,
        Currency tokenOut,
        int24 tickSpacing,
        uint256 amountOut,
        uint256 amountInMaximum
    ) internal returns (uint128) {
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut = _getFullDebt(tokenOut).toUint128();
        } else if (amountOut == ActionConstants.CONTRACT_BALANCE) {
            amountOut = tokenOut.balanceOfSelf().toUint128();
        }

        IERC20(Currency.unwrap(tokenIn)).approve(address(aerodromeRouter), amountInMaximum);

        uint256 amountIn = aerodromeRouter.exactOutputSingle(
            IAerodromeSwapRouter.ExactOutputSingleParams({
                tokenIn: Currency.unwrap(tokenIn),
                tokenOut: Currency.unwrap(tokenOut),
                tickSpacing: tickSpacing,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            })
        );
        return uint128(amountIn);
    }
}
