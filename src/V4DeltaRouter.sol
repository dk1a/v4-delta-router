// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26;

import { Currency, CurrencyLibrary } from "@uniswap/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { IPoolManager } from "@uniswap/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";

import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { BaseActionsRouter } from "@uniswap/v4-periphery/src/base/BaseActionsRouter.sol";
import { ReentrancyLock } from "@uniswap/v4-periphery/src/base/ReentrancyLock.sol";
import { Permit2Forwarder, IAllowanceTransfer } from "@uniswap/v4-periphery/src/base/Permit2Forwarder.sol";
import { NativeWrapper, IWETH9 } from "@uniswap/v4-periphery/src/base/NativeWrapper.sol";
import { CalldataDecoder } from "@uniswap/v4-periphery/src/libraries/CalldataDecoder.sol";
import { BipsLibrary } from "@uniswap/v4-periphery/src/libraries/BipsLibrary.sol";

import { Actions } from "./Actions.sol";
import { UniswapV4Actions } from "./modules/UniswapV4Actions.sol";

import { IV3Router } from "./modules/v3/IV3Router.sol";
import { V3CalldataDecoder } from "./modules/v3/V3CalldataDecoder.sol";
import { AerodromeActions } from "./modules/aerodrome/AerodromeActions.sol";

contract V4DeltaRouter is
    BaseActionsRouter,
    Permit2Forwarder,
    NativeWrapper,
    UniswapV4Actions,
    AerodromeActions,
    ReentrancyLock
{
    using CalldataDecoder for bytes;
    using BipsLibrary for uint256;

    constructor(
        address _permit2,
        address _weth,
        address _poolManager,
        address _aerodromeRouter
    )
        BaseActionsRouter(IPoolManager(_poolManager))
        Permit2Forwarder(IAllowanceTransfer(_permit2))
        NativeWrapper(IWETH9(_weth))
        AerodromeActions(_aerodromeRouter)
    {}

    /// @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
    /// times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
    /// @dev overrides BaseActionsRouter.msgSender in V4Router
    function msgSender() public view override returns (address) {
        return _getLocker();
    }

    function execute(bytes calldata inputs) public payable isNotLocked {
        _executeActions(inputs);
    }

    // implementation of abstract function DeltaResolver._pay
    function _pay(Currency currency, address payer, uint256 amount) internal override {
        if (payer == address(this)) {
            currency.transfer(address(poolManager), amount);
        } else {
            // Casting from uint256 to uint160 is safe due to limits on the total supply of a pool
            permit2.transferFrom(payer, address(poolManager), uint160(amount), Currency.unwrap(currency));
        }
    }

    function _handleAction(uint256 action, bytes calldata params) internal virtual override {
        // swap actions and payment actions in different blocks for gas efficiency
        if (action < Actions.SETTLE) {
            if (action == Actions.SWAP_EXACT_IN) {
                IV4Router.ExactInputParams calldata swapParams = params.decodeSwapExactInParams();
                _swapExactInput(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams calldata swapParams = params.decodeSwapExactInSingleParams();
                _swapExactInputSingle(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT) {
                IV4Router.ExactOutputParams calldata swapParams = params.decodeSwapExactOutParams();
                _swapExactOutput(swapParams);
                return;
            } else if (action == Actions.SWAP_EXACT_OUT_SINGLE) {
                IV4Router.ExactOutputSingleParams calldata swapParams = params.decodeSwapExactOutSingleParams();
                _swapExactOutputSingle(swapParams);
                return;
            }
        } else if (action < Actions.PERMIT2_PERMIT) {
            if (action == Actions.SETTLE_ALL) {
                (Currency currency, uint256 maxAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = _getFullDebt(currency);
                if (amount > maxAmount) revert V4TooMuchRequested(maxAmount, amount);
                _settle(currency, msgSender(), amount);
                return;
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency, uint256 minAmount) = params.decodeCurrencyAndUint256();
                uint256 amount = _getFullCredit(currency);
                if (amount < minAmount) revert V4TooLittleReceived(minAmount, amount);
                _take(currency, msgSender(), amount);
                return;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = params.decodeCurrencyUint256AndBool();
                _settle(currency, _mapPayer(payerIsUser), _mapSettleAmount(amount, currency));
                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = params.decodeCurrencyAddressAndUint256();
                _take(currency, _mapRecipient(recipient), _mapTakeAmount(amount, currency));
                return;
            } else if (action == Actions.TAKE_PORTION) {
                (Currency currency, address recipient, uint256 bips) = params.decodeCurrencyAddressAndUint256();
                _take(currency, _mapRecipient(recipient), _getFullCredit(currency).calculatePortion(bips));
                return;
            } else if (action == Actions.SWEEP) {
                (Currency currency, address to) = params.decodeCurrencyAndAddress();
                _sweep(currency, _mapRecipient(to));
                return;
            } else if (action == Actions.WRAP) {
                uint256 amount = params.decodeUint256();
                _wrap(_mapWrapUnwrapAmount(CurrencyLibrary.ADDRESS_ZERO, amount, Currency.wrap(address(WETH9))));
                return;
            } else if (action == Actions.UNWRAP) {
                uint256 amount = params.decodeUint256();
                _unwrap(_mapWrapUnwrapAmount(Currency.wrap(address(WETH9)), amount, CurrencyLibrary.ADDRESS_ZERO));
                return;
            }
        } else {
            if (action == Actions.PERMIT2_PERMIT) {
                // equivalent: abi.decode(params, (IAllowanceTransfer.PermitSingle, bytes))
                IAllowanceTransfer.PermitSingle calldata permitSingle;
                assembly {
                    permitSingle := params.offset
                }
                bytes calldata data = params.toBytes(6); // PermitSingle takes first 6 slots (0..5)
                permit2.permit(msgSender(), permitSingle, data);
                return;
            } else if (action == Actions.PERMIT2_TRANSFER_FROM) {
                // equivalent: abi.decode(params, (address, address, uint160))
                address token;
                address recipient;
                uint160 amount;
                assembly {
                    token := calldataload(params.offset)
                    recipient := calldataload(add(params.offset, 0x20))
                    amount := calldataload(add(params.offset, 0x40))
                }
                permit2.transferFrom(msgSender(), _mapRecipient(recipient), amount, token);
                return;
            } else if (action == uint256(Actions.AERODROME_SWAP_EXACT_IN)) {
                IV3Router.V3ExactInputParams calldata swapParams = V3CalldataDecoder.decodeSwapExactInParams(params);
                _aerodromeSwapExactInput(swapParams);
                return;
            } else if (action == uint256(Actions.AERODROME_SWAP_EXACT_OUT)) {
                IV3Router.V3ExactOutputParams calldata swapParams = V3CalldataDecoder.decodeSwapExactOutParams(params);
                _aerodromeSwapExactOutput(swapParams);
                return;
            }
        }
        revert UnsupportedAction(action);
    }

    /// @notice Sweeps the entire contract balance of specified currency to the recipient
    function _sweep(Currency currency, address to) internal {
        uint256 balance = currency.balanceOfSelf();
        if (balance > 0) currency.transfer(to, balance);
    }
}
