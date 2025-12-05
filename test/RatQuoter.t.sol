// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { IHooks } from "@uniswap/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-periphery/lib/v4-core/src/types/Currency.sol";

import { RatQuoter } from "../src/RatQuoter.sol";

uint256 constant BASE_MAINNET_CHAIN_ID = 8453;

// Base Mainnet fork tests
contract RatQuoterForkTest is Test {
    address constant weth = 0x4200000000000000000000000000000000000006;
    address constant eurc = 0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42;
    address constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address ratToken = 0xf2DD384662411A21259ab17038574289091F2D41;

    bytes pathWethToEurc;
    bytes pathEurcToWeth;
    PoolKey poolKey;

    RatQuoter ratQuoter;

    function setUp() public {
        address uniswapV4Quoter = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;
        vm.label(uniswapV4Quoter, "Uniswap V4 Quoter");
        // the newer one is 0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C but eurc pools use the legacy one
        address aerodromeQuoter = 0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0;
        vm.label(aerodromeQuoter, "legacy Aerodrome Quoter");

        ratQuoter = new RatQuoter(uniswapV4Quoter, aerodromeQuoter);

        pathWethToEurc = abi.encodePacked(weth, int24(100), eurc);
        pathEurcToWeth = abi.encodePacked(eurc, int24(100), weth);

        poolKey = PoolKey({
            currency0: Currency.wrap(eurc),
            currency1: Currency.wrap(address(ratToken)),
            fee: 8388608,
            tickSpacing: 30,
            hooks: IHooks(0x20A265758c73BCebEa0dc7eadA74DFB380C6f8e0)
        });
    }

    function _warpAuctionStart() internal {
        vm.warp(1765292400);
    }

    function _warpBeforeAuctionEnd() internal {
        vm.warp(1767970800 - 100);
    }

    function _warpAfterAuctionEnd() internal {
        vm.warp(1767970800);
    }

    function testQuoteExactOut() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        _warpAuctionStart();

        (uint256 amountInInitial, uint256 amountInUniswap) = ratQuoter.quoteExactOut(
            1000e18,
            pathEurcToWeth,
            poolKey,
            true
        );

        // At the start 1000 RAT ~= 0.0053 WETH and 14 EURC
        assertApproxEqRel(amountInInitial, 0.0053e18, 0.10e18);
        assertApproxEqRel(amountInUniswap, 14e6, 0.10e18);

        _warpBeforeAuctionEnd();

        (amountInInitial, amountInUniswap) = ratQuoter.quoteExactOut(
            1000e18,
            pathEurcToWeth,
            poolKey,
            true
        );

        // At the end 1000 RAT ~= 0.0019 WETH and 5 EURC
        assertApproxEqRel(amountInInitial, 0.0019e18, 0.10e18);
        assertApproxEqRel(amountInUniswap, 5e6, 0.10e18);
    }
}
