// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { PoolKey } from "@uniswap/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { IV4Quoter } from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import { IAerodromeQuoter } from "./modules/aerodrome/AerodromeInterfaces.sol";

contract RatQuoter {
    IV4Quoter public immutable uniswapV4Quoter;
    IAerodromeQuoter public immutable aerodromeQuoter;

    constructor(address _uniswapV4Quoter, address _aerodromeQuoter) {
        uniswapV4Quoter = IV4Quoter(_uniswapV4Quoter);
        aerodromeQuoter = IAerodromeQuoter(_aerodromeQuoter);
    }

    function quoteExactIn(
        uint256 amountIn,
        bytes memory aerodromePath,
        PoolKey memory uniswapPoolKey,
        bool uniswapZeroForOne
    ) external returns (uint256 amountOutFinal, uint256 amountInUniswap) {
        (amountInUniswap, , , ) = aerodromeQuoter.quoteExactInput(aerodromePath, amountIn);

        (amountOutFinal, ) = uniswapV4Quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: uniswapPoolKey,
                zeroForOne: uniswapZeroForOne,
                exactAmount: uint128(amountInUniswap),
                hookData: ""
            })
        );
    }

    function quoteExactOut(
        uint128 amountOut,
        bytes memory aerodromePath,
        PoolKey memory uniswapPoolKey,
        bool uniswapZeroForOne
    ) external returns (uint256 amountInInitial, uint256 amountInUniswap) {
        (amountInUniswap, ) = uniswapV4Quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: uniswapPoolKey,
                zeroForOne: uniswapZeroForOne,
                exactAmount: amountOut,
                hookData: ""
            })
        );

        (amountInInitial, , , ) = aerodromeQuoter.quoteExactOutput(aerodromePath, amountInUniswap);
    }
}
