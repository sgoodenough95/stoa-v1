// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AppStorage,
    RefTokenParams
} from "./../libs/LibAppStorage.sol";
import { LibToken } from "./../libs/LibToken.sol";
import "./../interfaces/IStoa.sol";
import "./../interfaces/IStoaToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  ExchangeFacet
/// @author The Stoa Corporation Ltd.
/// @notice User-facing functions for exchanging tokens.
contract ExchangeFacet {
    AppStorage internal s;

    function underlyingToActive(
        address activeToken,
        uint256 amount, // The amount of underlyingTokens.
        uint256 minAmountOut,   // The min amount of vaultTokens issued.
        address depositFrom,
        address recipient
    ) external returns (uint256 activeAmount) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        // Before depositing, the underlyingTokens must be wrapped into vaultTokens.
        uint256 shares = LibToken._wrap(activeToken, amount, depositFrom);
        if (shares < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        activeAmount = LibToken._mintActiveFromVault(activeToken, shares, recipient);
    }

    function underlyingToUnactive(
        address activeToken,
        uint256 amount, // The amount of underlyingTokens.
        uint256 minAmountOut,   // The min amount of vaultTokens issued.
        address depositFrom,
        address recipient
    ) external returns (uint256 stoaTokens) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        // Before depositing, the underlying tokens must be wrapped into yield tokens.
        uint256 shares = LibToken._wrap(activeToken, amount, depositFrom);
        if (shares < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        stoaTokens = LibToken._mintUnactiveFromVault(activeToken, shares, recipient);
    }

    function vaultToActive(
        address activeToken,
        uint256 shares, // The amount of vaultTokens.
        address depositFrom,
        address recipient
    ) external returns (uint256 stoaTokens) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);

        // Only consider minDeposit for underlyingToken.
        if (assets < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(assets);
        }

        SafeERC20.safeTransferFrom(IERC20(refTokenParams.vaultToken), depositFrom, address(this), shares);

        stoaTokens = LibToken._mintActiveFromVault(activeToken, shares, recipient);
    }

    function vaultToUnactive(
        address activeToken,
        uint256 shares, // The amount of vaultTokens.
        address depositFrom,
        address recipient
    ) external returns (uint256 stoaTokens) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);

        // Only consider minDeposit for underlyingToken.
        if (assets < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(assets);  //
        }

        SafeERC20.safeTransferFrom(IERC20(refTokenParams.vaultToken), depositFrom, address(this), shares);

        stoaTokens = LibToken._mintUnactiveFromVault(activeToken, shares, recipient);
    }

    function activeToUnactive(
        address activeToken,
        uint256 amount, // The amount of activeTokens.
        address depositFrom,
        address recipient
    ) external returns (uint256 unactiveTokens) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        // First, transfer activeTokens to Stoa.
        SafeERC20.safeTransferFrom(IERC20(activeToken), depositFrom, address(this), amount);

        unactiveTokens = LibToken._mintUnactiveDetailed(activeToken, amount, recipient, 3, 1, 1);
    }

    function activeToVault(
        address activeToken,
        uint256 amount,  // The amount of activeTokens.
        uint256 minAmountOut,   // The min amount of vaultTokens received.
        address withdrawFrom,
        address recipient
    ) external returns (uint256 shares) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Only consider minWithdraw for the underlyingToken.
        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }

        // First, transfer activeTokens to Stoa.
        SafeERC20.safeTransferFrom(IERC20(activeToken), withdrawFrom, address(this), amount);

        shares = LibToken._burnActive(activeToken, amount, address(0), 2);
        if (shares < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        // Transfer vaultTokens to user.
        SafeERC20.safeTransfer(IERC20(refTokenParams.vaultToken), recipient, shares);
    }

    function activeToUnderlying(
        address activeToken,
        uint256 amount, // The amount of activeTokens.
        uint256 minAmountOut,
        address withdrawFrom,
        address recipient
    ) external returns (uint256 assets) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }

        // First, transfer activeTokens to Stoa.
        SafeERC20.safeTransferFrom(IERC20(activeToken), withdrawFrom, address(this), amount);

        uint256 shares = LibToken._burnActive(activeToken, amount, recipient, 2);
        assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);
        if (assets < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(assets, minAmountOut);
        }
    }

    function unactiveToActive(
        address activeToken,
        uint256 amount, // The amount of unactiveTokens
        address withdrawFrom,
        address recipient
    ) external returns (uint256 assets) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }
        if (amount < s.claimableUnactiveBackingReserves[activeToken]) {
            revert IStoaErrors.InsufficientClaimableReserves(amount);
        }
        if (amount < s._unactiveRedemptions[msg.sender][activeToken]) {
            revert IStoaErrors.InsufficientRedemptionAllowance(amount);
        }

        (, assets)
            = LibToken._burnUnactive(activeToken, amount, withdrawFrom, address(0), 3);

        SafeERC20.safeTransfer(IERC20(activeToken), recipient, assets);
    }

    function unactiveToVault(
        address activeToken,
        uint256 amount, // The amount of unactiveTokens
        uint256 minAmountOut,
        address withdrawFrom,
        address recipient
    ) external returns (uint256 shares, uint256 assets) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }
        if (amount < s.claimableUnactiveBackingReserves[activeToken]) {
            revert IStoaErrors.InsufficientClaimableReserves(amount);
        }
        if (amount < s._unactiveRedemptions[msg.sender][activeToken]) {
            revert IStoaErrors.InsufficientRedemptionAllowance(amount);
        }

        // Apply redemptionFee during next step, otherwise charging double fees.
        (, assets)
            = LibToken._burnUnactive(activeToken, amount, withdrawFrom, address(0), 0);

        shares = LibToken._burnActive(activeToken, assets, address(0), 2);
        if (shares < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        // Transfer vaultTokens to user.
        SafeERC20.safeTransfer(IERC20(refTokenParams.vaultToken), recipient, shares);
    }

    function unactiveToUnderlying(
        address activeToken,
        uint256 amount, // The amount of unactiveTokens
        uint256 minAmountOut,   // The min amount of underlyingTokens received.
        address withdrawFrom,
        address recipient
    ) external returns (uint256 shares, uint256 assets) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }
        if (amount < s.claimableUnactiveBackingReserves[activeToken]) {
            revert IStoaErrors.InsufficientClaimableReserves(amount);
        }
        if (amount < s._unactiveRedemptions[msg.sender][activeToken]) {
            revert IStoaErrors.InsufficientRedemptionAllowance(amount);
        }

        // Apply redemptionFee during next step, otherwise charging double fees.
        (, assets)
            = LibToken._burnUnactive(activeToken, amount, withdrawFrom, address(0), 0);

        shares = LibToken._burnActive(activeToken, assets, recipient, 2);
        assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);
        if (assets < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(assets, minAmountOut);
        }
    }
}