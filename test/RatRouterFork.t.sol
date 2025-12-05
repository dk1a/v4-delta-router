// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IHooks } from "@uniswap/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "@uniswap/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {
    Currency,
    CurrencyLibrary
} from "@uniswap/v4-periphery/lib/v4-core/src/types/Currency.sol";

import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { ActionConstants } from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";

import { IV3Router } from "../src/modules/v3/IV3Router.sol";
import { V4DeltaRouter } from "../src/V4DeltaRouter.sol";
import { Actions } from "../src/Actions.sol";
import { SWAP_CONTRACT_BALANCE } from "../src/modules/UniswapV4Actions.sol";

interface IDERC20BuyLimit is IERC20 {
    function setCountryCode(string calldata countryCode) external;
}

uint256 constant BASE_MAINNET_CHAIN_ID = 8453;

// Base Mainnet fork tests
contract RatRouterForkTest is Test {
    address constant weth = 0x4200000000000000000000000000000000000006;
    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant eurc = 0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42;
    address constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    V4DeltaRouter constant router =
        V4DeltaRouter(payable(address(bytes20(keccak256("router test address")))));
    IDERC20BuyLimit ratToken = IDERC20BuyLimit(0xf2DD384662411A21259ab17038574289091F2D41);

    // random account with private key = 0x66476b9354ab18d457adaaa4236c169c0368a7c9b3fc926e5a54e82d0429864f
    address alice = 0x02435BA6eF2Df8163039D66283BFA03e12Bf624F;

    bytes pathWethToEurc;
    bytes pathEurcToWeth;
    PoolKey poolKey;
    IAllowanceTransfer.PermitSingle usdcPermit;
    bytes usdcPermitSignature;

    function setUp() public {
        _deployCodeToRouter();

        vm.label(weth, "WETH9");
        vm.label(permit2, "PERMIT2");
        vm.label(eurc, "EURC");
        vm.label(usdc, "USDC");
        vm.label(address(router), "V4DeltaRouter");
        vm.label(address(ratToken), "RAT");
        vm.label(alice, "Alice");

        vm.label(0xE846373C1a92B167b4E9cd5d8E4d6B1Db9E90EC7, "Aerodrome CLPool EURC-USDC");
        vm.label(0x5d4e504EB4c526995E0cC7A6E327FDa75D8B52b5, "Aerodrome CLPool WETH-EURC");

        pathWethToEurc = abi.encodePacked(weth, int24(100), eurc);
        pathEurcToWeth = abi.encodePacked(eurc, int24(100), weth);

        poolKey = PoolKey({
            currency0: Currency.wrap(eurc),
            currency1: Currency.wrap(address(ratToken)),
            fee: 8388608,
            tickSpacing: 30,
            hooks: IHooks(0x20A265758c73BCebEa0dc7eadA74DFB380C6f8e0)
        });

        // Alice's max approval for permit2 to spend USDC
        vm.prank(alice);
        IERC20(usdc).approve(permit2, type(uint256).max);

        // Alice's permit and signature for 1000 USDC
        usdcPermit = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: usdc,
                amount: 1000000000,
                expiration: 1765296000,
                nonce: 0
            }),
            spender: address(router),
            sigDeadline: 1765296000
        });
        usdcPermitSignature = hex"e931cf264d22a1810ab2cd10011c4afd794f5ac8b8c675671b6b59d10f7af64d42a940a7a6a73ab873c0226c056c16943a83bfd2c868832e2e55212838152ded1c";
    }

    function _deployCodeToRouter() internal {
        address poolManager = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        vm.label(poolManager, "Uniswap PoolManager");
        // the newer one is 0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D but eurc pools use the legacy one
        address aerodromeRouter = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
        vm.label(aerodromeRouter, "legacy Aerodrome Router");

        deployCodeTo(
            "V4DeltaRouter.sol",
            abi.encode(permit2, weth, poolManager, aerodromeRouter),
            address(router)
        );
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

    function _exactInDataEth(
        uint128 amountIn,
        uint128 amountOutMinimum
    ) internal view returns (bytes memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.WRAP),
            uint8(Actions.AERODROME_SWAP_EXACT_IN),
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](5);
        params[0] = abi.encode(ActionConstants.CONTRACT_BALANCE);
        params[1] = abi.encode(
            IV3Router.V3ExactInputParams({
                path: abi.encodePacked(weth, int24(100), eurc),
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
        params[2] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: SWAP_CONTRACT_BALANCE,
                amountOutMinimum: amountOutMinimum,
                hookData: ""
            })
        );
        params[3] = abi.encode(eurc, ActionConstants.OPEN_DELTA, false);
        params[4] = abi.encode(ratToken, 1);

        return abi.encode(actions, params);
    }

    // Permit is 1000e6 (USDC is 6 decimals)
    function _exactInDataUsdc(
        uint128 amountIn,
        uint128 amountOutMinimum
    ) internal view returns (bytes memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.PERMIT2_PERMIT),
            uint8(Actions.PERMIT2_TRANSFER_FROM),
            uint8(Actions.AERODROME_SWAP_EXACT_IN),
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](6);
        params[0] = abi.encode(usdcPermit, usdcPermitSignature);
        params[1] = abi.encode(usdc, ActionConstants.ADDRESS_THIS, amountIn);
        params[2] = abi.encode(
            IV3Router.V3ExactInputParams({
                path: abi.encodePacked(usdc, int24(50), eurc),
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
        params[3] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: SWAP_CONTRACT_BALANCE,
                amountOutMinimum: amountOutMinimum,
                hookData: ""
            })
        );
        params[4] = abi.encode(eurc, ActionConstants.OPEN_DELTA, false);
        params[5] = abi.encode(ratToken, 1);

        return abi.encode(actions, params);
    }

    function _exactOutDataEth(
        uint128 amountOut,
        uint128 amountInMaximum
    ) internal view returns (bytes memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.WRAP),
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.AERODROME_SWAP_EXACT_OUT),
            uint8(Actions.SETTLE),
            uint8(Actions.TAKE_ALL),
            uint8(Actions.UNWRAP),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](7);
        params[0] = abi.encode(ActionConstants.CONTRACT_BALANCE);
        params[1] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountOut: amountOut,
                amountInMaximum: type(uint128).max,
                hookData: ""
            })
        );
        params[2] = abi.encode(
            IV3Router.V3ExactOutputParams({
                path: abi.encodePacked(eurc, int24(100), weth),
                amountOut: ActionConstants.OPEN_DELTA,
                amountInMaximum: amountInMaximum
            })
        );
        params[3] = abi.encode(eurc, ActionConstants.OPEN_DELTA, false);
        params[4] = abi.encode(ratToken, 1);
        params[5] = abi.encode(ActionConstants.CONTRACT_BALANCE);
        params[6] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, ActionConstants.MSG_SENDER);

        return abi.encode(actions, params);
    }

    // Permit is 1000e6 (USDC is 6 decimals)
    function _exactOutDataUsdc(
        uint128 amountOut,
        uint128 amountInMaximum
    ) internal view returns (bytes memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.PERMIT2_PERMIT),
            uint8(Actions.PERMIT2_TRANSFER_FROM),
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.AERODROME_SWAP_EXACT_OUT),
            uint8(Actions.SETTLE),
            uint8(Actions.TAKE_ALL),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](7);
        params[0] = abi.encode(usdcPermit, usdcPermitSignature);
        params[1] = abi.encode(usdc, ActionConstants.ADDRESS_THIS, amountInMaximum);
        params[2] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountOut: amountOut,
                amountInMaximum: type(uint128).max,
                hookData: ""
            })
        );
        params[3] = abi.encode(
            IV3Router.V3ExactOutputParams({
                path: abi.encodePacked(eurc, int24(50), usdc),
                amountOut: ActionConstants.OPEN_DELTA,
                amountInMaximum: amountInMaximum
            })
        );
        params[4] = abi.encode(eurc, ActionConstants.OPEN_DELTA, false);
        params[5] = abi.encode(ratToken, 1);
        params[6] = abi.encode(usdc, ActionConstants.MSG_SENDER);

        return abi.encode(actions, params);
    }

    function testSwapExactInEth() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        uint128 amountIn = 0.344 ether;
        uint128 amountOutMinimum = 64_900e18;

        _warpAuctionStart();
        vm.startPrank(alice);
        vm.deal(alice, amountIn);
        ratToken.setCountryCode("RU");

        bytes memory data = _exactInDataEth(amountIn, amountOutMinimum);

        uint256 gas = gasleft();
        router.execute{ value: amountIn }(data);
        gas -= gasleft();
        console.log("swapExactInEth gas", gas);

        // At the start 0.344 ETH ~= 65_000 RAT
        assertApproxEqRel(ratToken.balanceOf(alice), 65_000e18, 0.01e18);
        assertEq(alice.balance, 0);
    }

    function testSwapExactInUsdc() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        uint128 amountIn = 1000e6;
        uint128 amountOutMinimum = 60_900e18;

        _warpAuctionStart();
        vm.startPrank(alice);
        deal(usdc, alice, amountIn);
        ratToken.setCountryCode("RU");

        bytes memory data = _exactInDataUsdc(amountIn, amountOutMinimum);

        uint256 gas = gasleft();
        router.execute(data);
        gas -= gasleft();
        console.log("swapExactInUsdc gas", gas);

        // At the start 1000 USDC ~= 60_900 RAT
        assertApproxEqRel(ratToken.balanceOf(alice), 60_900e18, 0.01e18);
        assertEq(IERC20(usdc).balanceOf(alice), 0);
    }

    function testSwapExactOutEth() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        uint128 amountOut = 65_000e18;
        uint128 amountInMaximum = 0.4 ether;

        _warpAuctionStart();
        vm.startPrank(alice);
        vm.deal(alice, amountInMaximum);
        ratToken.setCountryCode("RU");

        bytes memory data = _exactOutDataEth(amountOut, amountInMaximum);

        uint256 gas = gasleft();
        router.execute{ value: amountInMaximum }(data);
        gas -= gasleft();
        console.log("swapExactOutEth gas", gas);

        // At the start 0.344 ETH ~= 65_000 RAT
        assertEq(ratToken.balanceOf(alice), amountOut);
        assertApproxEqRel(alice.balance, amountInMaximum - 0.344 ether, 0.01e18);
    }

    function testSwapExactOutUsdc() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        uint128 amountOut = 60_900e18;
        uint128 amountInMaximum = 1000e6;

        _warpAuctionStart();
        vm.startPrank(alice);
        deal(usdc, alice, amountInMaximum);
        ratToken.setCountryCode("RU");

        bytes memory data = _exactOutDataUsdc(amountOut, amountInMaximum);

        uint256 gas = gasleft();
        router.execute(data);
        gas -= gasleft();
        console.log("swapExactOutUsdc gas", gas);

        // At the start 1000 USDC ~= 60_900 RAT
        assertEq(ratToken.balanceOf(alice), amountOut);
        assertApproxEqAbs(IERC20(usdc).balanceOf(alice), 0, 0.3e6);
    }

    function testRevertExceedLimit() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        _warpAuctionStart();
        vm.startPrank(alice);
        vm.deal(alice, 0.4 ether);
        ratToken.setCountryCode("RU");

        vm.expectRevert();
        router.execute{ value: 0.38 ether }(_exactInDataEth(0.38 ether, 0));

        router.execute{ value: 0.34 ether }(_exactInDataEth(0.34 ether, 0));

        vm.expectRevert();
        router.execute{ value: 0.04 ether }(_exactInDataEth(0.04 ether, 0));
    }

    function testRevertNotOngoing() public {
        vm.skip(block.chainid != BASE_MAINNET_CHAIN_ID);

        vm.startPrank(alice);
        vm.deal(alice, 0.4 ether);
        ratToken.setCountryCode("RU");

        vm.expectRevert();
        router.execute{ value: 0.1 ether }(_exactInDataEth(0.1 ether, 0));

        _warpAfterAuctionEnd();

        vm.expectRevert();
        router.execute{ value: 0.1 ether }(_exactInDataEth(0.1 ether, 0));
    }
}
