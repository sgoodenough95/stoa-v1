// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import {
    AppStorage,
    RefTokenParams
} from "./../libs/LibAppStorage.sol";
import { LibToken } from "./../libs/LibToken.sol";
import { LibSafe } from "./../libs/LibSafe.sol";
import { IERC4626 } from ".././interfaces/IERC4626.sol";
import "./../interfaces/IStoa.sol";
import "./../interfaces/IStoaToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  SafeFacet
/// @author The Stoa Corporation Ltd.
/// @notice User-facing functions for managing Safes.
///
/// @notice This MVP does not consider RWAs/off-chain/multiple vaults.
///
/// @dev    Keep transacting with vaultTokens for now, may later remove.
contract SafeFacet {
    AppStorage internal s;

    /// @notice Open a Safe with an underlyingToken (e.g., USDC).
    function openWithUnderlying(
        address activeToken,
        uint256 amount,
        uint256 minAmountOut,   // FIX
        address depositFrom
    ) external returns (uint256 activeAmount, uint256 shares) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        // Before depositing, the underlyingTokens must be wrapped into vaultTokens.
        uint256 vaultAmount = LibToken._wrap(activeToken, amount, depositFrom);
        if (vaultAmount < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        // Mint activeTokens to self.
        activeAmount = LibToken._mintActiveFromVault(activeToken, shares, address(this));

        // Deposit activeTokens into respective Safe Store.
        shares =
            IERC4626(refTokenParams.safeStore).deposit(activeAmount, address(this), address(this));

        LibSafe._initializeSafe(msg.sender, activeToken, shares);
    }

    /// @notice Open a Safe with a vaultToken (e.g., yvUSDC).
    function openWithVault(
        address activeToken,
        uint256 amount,
        address depositFrom
    ) external returns (uint256 activeAmount, uint256 shares) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 assets = LibToken._previewRedeem(refTokenParams.vaultToken, amount);

        // Only consider minDeposit for underlyingToken.
        if (assets < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(assets);
        }

        SafeERC20.
            safeTransferFrom(IERC20(refTokenParams.vaultToken), depositFrom, address(this), amount);

        activeAmount = LibToken._mintActiveFromVault(activeToken, amount, address(this));

        // Deposit activeTokens into respective Safe Store.
        shares =
            IERC4626(refTokenParams.safeStore).deposit(activeAmount, address(this), address(this));

        LibSafe._initializeSafe(msg.sender, activeToken, shares);
    }

    /// @notice Open a Safe with an activeToken (e.g., USDSTA).
    function openWithActive(
        address activeToken,
        uint256 amount,
        address depositFrom
    ) external returns (uint256 shares) {
        LibToken._ensureEnabled(activeToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Only consider minDeposit for underlyingToken.
        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        SafeERC20.safeTransferFrom(IERC20(activeToken), depositFrom, address(this), amount);

        // Deposit activeTokens into respective Safe Store.
        shares =
            IERC4626(refTokenParams.safeStore).deposit(amount, address(this), address(this));

        LibSafe._initializeSafe(msg.sender, activeToken, shares);
    }

    /// @notice Deposit an underlyingToken to an active Safe, which is minted activeTokens.
    function depositUnderlying(
        uint256 index,
        uint256 amount,
        uint256 minAmountOut,
        address depositFrom
    ) external returns (uint256 activeAmount, uint256 shares) {
        address activeToken = s.safe[msg.sender][index].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][index].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][index].owner, msg.sender);
        }
        if (s.safe[msg.sender][index].status != 1 || s.safe[msg.sender][index].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][index].owner, index);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        // Before depositing, the underlyingTokens must be wrapped into vaultTokens.
        shares = LibToken._wrap(activeToken, amount, depositFrom);
        if (shares < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        // Transfer activeTokens to the respective safeStore contract.
        activeAmount = LibToken._mintActiveFromVault(activeToken, shares, address(this));
        
        shares =
            IERC4626(refTokenParams.safeStore).deposit(activeAmount, address(this), address(this));

        LibSafe._adjustSafeBal(msg.sender, index, int256(shares));
    }

    /// @notice Deposit a vaultToken to an active Safe, which is minted activeTokens.
    function depositVault(
        uint256 index,
        uint256 amount,
        address depositFrom
    ) external returns (uint256 activeAmount) {
        address activeToken = s.safe[msg.sender][index].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][index].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][index].owner, msg.sender);
        }
        if (s.safe[msg.sender][index].status != 1 || s.safe[msg.sender][index].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][index].owner, index);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 assets = LibToken._previewRedeem(refTokenParams.vaultToken, amount);

        // Only consider minDeposit for underlyingToken.
        if (assets < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(assets);
        }

        SafeERC20.
            safeTransferFrom(IERC20(refTokenParams.vaultToken), depositFrom, address(this), amount);

        activeAmount = LibToken._mintActiveFromVault(activeToken, amount, refTokenParams.safeStore);

        LibSafe._adjustSafeBal(msg.sender, index, int256(activeAmount));
    }
        
    function depositActive(
        uint256 index,
        uint256 amount,
        address depositFrom
    ) external returns (uint256 shares) {
        address activeToken = s.safe[msg.sender][index].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][index].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][index].owner, msg.sender);
        }
        if (s.safe[msg.sender][index].status != 1 || s.safe[msg.sender][index].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][index].owner, index);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Only consider minDeposit for underlyingToken.
        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientDepositAmount(amount);
        }

        shares = IERC4626(refTokenParams.safeStore).deposit(amount, address(this), depositFrom);

        LibSafe._adjustSafeBal(msg.sender, index, int256(shares));
    }

    function withdrawUnderlying(
        uint256 index,
        uint256 amount,         // The amount of activeTokens to burn.
        uint256 minAmountOut,   // minAmountOut of underlyingTokens from yield venue.
        address recipient
    ) external returns (uint256 assets) {
        address activeToken = s.safe[msg.sender][index].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][index].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][index].owner, msg.sender);
        }
        if (s.safe[msg.sender][index].status != 1 || s.safe[msg.sender][index].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][index].owner, index);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Only consider minWithdraw for underlyingToken.
        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }
        
        // The free activeAmount.
        ( , uint256 free) = LibSafe._getWithdrawAllowance(msg.sender, index);
        if (amount < free) {
            revert IStoaErrors.InsufficientSafeFreeBal(msg.sender, index);
        }

        LibSafe._adjustSafeBal(msg.sender, index, int(amount) * -1);

        uint256 shares = LibToken._burnActive(activeToken, amount, recipient, 2);
        assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);
        if (assets < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(assets, minAmountOut);
        }
    }

    function withdrawVault(
        uint256 index,
        uint256 amount,         // The amount of activeTokens to burn.
        uint256 minAmountOut,   // The min amount of vaultTokens received.
        address recipient
    ) external returns (uint256 shares) {
        address activeToken = s.safe[msg.sender][index].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][index].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][index].owner, msg.sender);
        }
        if (s.safe[msg.sender][index].status != 1 || s.safe[msg.sender][index].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][index].owner, index);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Only consider minWithdraw for underlyingToken.
        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }
        
        // The free activeAmount.
        ( , uint256 free) = LibSafe._getWithdrawAllowance(msg.sender, index);
        if (amount < free) {
            revert IStoaErrors.InsufficientSafeFreeBal(msg.sender, index);
        }

        LibSafe._adjustSafeBal(msg.sender, index, int(amount) * -1);

        shares = LibToken._burnActive(activeToken, amount, address(0), 2);
        if (shares < minAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minAmountOut);
        }

        // Transfer vaultTokens to user.
        SafeERC20.safeTransfer(IERC20(refTokenParams.vaultToken), recipient, shares);
    }

    function withdrawActive(
        uint256 index,
        uint256 amount,
        address recipient
    ) external {
        address activeToken = s.safe[msg.sender][index].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][index].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][index].owner, msg.sender);
        }
        if (s.safe[msg.sender][index].status != 1 || s.safe[msg.sender][index].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][index].owner, index);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Only consider minWithdraw for underlyingToken.
        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }
        
        // The free activeAmount.
        ( , uint256 free) = LibSafe._getWithdrawAllowance(msg.sender, index);
        if (amount < free) {
            revert IStoaErrors.InsufficientSafeFreeBal(msg.sender, index);
        }

        LibSafe._adjustSafeBal(msg.sender, index, int(amount) * -1);

        // Transfer activeTokens.
        SafeERC20.safeTransfer(IERC20(activeToken), recipient, amount);
    }
    
    function transferBal(
        address to,
        uint256 toIndex,
        uint256 fromIndex,
        uint256 amount
    ) external {
        address activeToken = s.safe[msg.sender][fromIndex].activeToken;

        LibToken._ensureEnabled(activeToken);

        // Check if the caller is the Safe owner.
        if (s.safe[msg.sender][fromIndex].owner != msg.sender) {
            revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][fromIndex].owner, msg.sender);
        }
        if (s.safe[msg.sender][fromIndex].status != 1 || s.safe[msg.sender][fromIndex].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[msg.sender][fromIndex].owner, fromIndex);
        }

        // Check if the recipient Safe is active.
        if (s.safe[to][toIndex].status != 1 || s.safe[to][toIndex].status != 2) {
            revert IStoaErrors.SafeNotActive(s.safe[to][toIndex].owner, toIndex);
        }
        // Check if the recipient Safe supports the activeToken.
        if (s.safe[to][toIndex].activeToken != s.safe[msg.sender][fromIndex].activeToken) {
            revert IStoaErrors.IllegalSafeTransfer(to, toIndex, fromIndex);
        }

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Treat min transfer as minWithdraw for now.
        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.InsufficientWithdrawAmount(amount);
        }

        // The free activeAmount.
        ( , uint256 free) = LibSafe._getWithdrawAllowance(msg.sender, fromIndex);
        if (amount < free) {
            revert IStoaErrors.InsufficientSafeFreeBal(msg.sender, fromIndex);
        }

        LibSafe._adjustSafeBal(msg.sender, fromIndex, int(amount) * -1);

        LibSafe._adjustSafeBal(to, toIndex, int(amount));
    }

    // function transferDebt(
    //     uint256 toIndex,
    //     uint256 fromIndex,
    //     uint256 amount
    // ) external {
    //     address activeToken = s.safe[msg.sender][fromIndex].activeToken;

    //     LibToken._ensureEnabled(activeToken);

    //     // Check if the caller is the Safe owner.
    //     if (s.safe[msg.sender][fromIndex].owner != msg.sender) {
    //         revert IStoaErrors.SafeOwnerMismatch(s.safe[msg.sender][fromIndex].owner, msg.sender);
    //     }
    //     if (s.safe[msg.sender][fromIndex].status != 1 || s.safe[msg.sender][fromIndex].status != 2) {
    //         revert IStoaErrors.SafeNotActive(s.safe[msg.sender][fromIndex].owner, fromIndex);
    //     }

    //     // Check if the recipient Safe is active.
    //     if (s.safe[msg.sender][toIndex].status != 1 || s.safe[msg.sender][toIndex].status != 2) {
    //         revert IStoaErrors.SafeNotActive(s.safe[msg.sender][toIndex].owner, toIndex);
    //     }
    //     // Check if the recipient Safe supports the debtToken.
    //     // The debtToken of the recipient Safe must already be initialized.
    //     // Need to check how much debt the recipient Safe can support.
    //     if (s.safe[msg.sender][toIndex].activeToken != s.safe[msg.sender][fromIndex].activeToken) {
    //         revert IStoaErrors.IllegalSafeTransfer(to, toIndex, fromIndex);
    //     }

    //     RefTokenParams memory refTokenParams = s._refTokens[activeToken];

    // }

    // function transferSafe(
    //     address to,
    //     uint256 index
    // ) external {

    // }
}