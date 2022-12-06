// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AppStorage,
    UnderlyingTokenParams,
    RefTokenParams,
    StoaTokenParams,
    ActivePoolTokenParams
} from ".././libs/LibAppStorage.sol";
import { LibToken } from ".././libs/LibToken.sol";
import ".././interfaces/IStoa.sol";
import ".././interfaces/IStoaToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  ControllerFacet
/// @author The Stoa Corporation Ltd.
/// @notice User-facing functions for direct deposits and withdrawals.
contract ControllerFacet {

    AppStorage internal s;

    /// @notice Non-custodial deposit of vaultToken (e.g., yvDAI).
    function depositVaultToken(
        address activeToken,
        uint256 shares, // The amount of vaultTokens.
        address depositFrom,
        address recipient,
        uint8   activated
    ) external returns (uint256 stoaTokens) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);

        // Only consider minDeposit for underlyingToken.
        if (assets < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }
        if (activated >= 2) {
            revert IStoaErrors.IllegalArgument(5);
        }

        LibToken._ensureEnabled(activeToken);

        SafeERC20.safeTransferFrom(IERC20(refTokenParams.vaultToken), depositFrom, address(this), shares);

        stoaTokens = LibToken._mint(activeToken, shares, recipient, activeToken);
    }

    /// @notice Non-custodial deposit of underlyingToken (e.g., DAI).
    function depositUnderlyingToken(
        address activeToken,
        uint256 amount, // The amount of underlyingTokens.
        uint256 minimumAmountOut,
        address depositFrom,
        address recipient,
        uint8   activated
    ) external returns (uint256 stoaTokens) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minDeposit[refTokenParams.underlyingToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        LibToken._ensureEnabled(activeToken);

        // Before depositing, the underlying tokens must be wrapped into yield tokens.
        uint256 shares = LibToken._wrap(activeToken, amount, depositFrom, minimumAmountOut);
        if (shares < minimumAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minimumAmountOut);
        }

        stoaTokens = LibToken._mint(activeToken, shares, recipient, activated);
    }

    /// @notice Withdrawal of vaultToken (e.g., yvDAI).
    function withdrawVaultToken(
        address activeToken,
        uint256 amount,  // The amount of activeTokens.
        uint256 minimumAmountOut,
        address withdrawFrom,
        address recipient
    ) external returns (uint256 shares) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minWithdraw[refTokenParams.vaultToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        // First, transfer activeTokens to Stoa.
        SafeERC20.safeTransferFrom(IERC20(activeToken), msg.sender, address(this), amount);

        shares = LibToken._burn(activeToken, amount, withdrawFrom, 0, 0);
        if (shares < minimumAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(shares, minimumAmountOut);
        }

        // Transfer vaultTokens to user.
        SafeERC20.safeTransfer(IERC20(refTokenParams.vaultToken), recipient, shares);
    }

    /// @notice Withdrawal of underlying tokens (e.g., DAI).
    function withdrawUnderlyingToken(
        address activeToken,
        uint256 amount, // The amount of activeTokens.
        uint256 minimumAmountOut,
        address withdrawFrom,
        address recipient
    ) external returns (uint256 assets) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        // First, transfer activeTokens to Stoa.
        SafeERC20.safeTransferFrom(IERC20(activeToken), withdrawFrom, address(this), amount);

        uint256 shares = LibToken._burn(activeToken, amount, withdrawer, 1, 0);
        assets = LibToken._previewRedeem(refTokenParams.vaultToken, shares);
        if (assets < minimumAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(assets, minimumAmountOut);
        }
    }

    function unactiveRedemption(
        address activeToken,
        uint256 amount,
        uint256 minimumAmountOut,
        address withdrawFrom,
        uint8   requestUnderlying   // Need to think as may have a few.
    ) external returns (uint256 shares, uint256 assets) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        if (requestUnderlying == 0) {
            if (amount < s.minWithdraw[refTokenParams.activeToken]) {
                revert IStoaErrors.IllegalArgument(1);
            }
        } else if (requestUnderlying == 1) {
            if (amount < s.minWithdraw[refTokenParams.underlyingToken]) {
                revert IStoaErrors.IllegalArgument(1);
            }
        } else {
            revert IStoaErrors.IllegalArgument(3);
        }

        if (s.unactiveRedemptionAllowance[refTokenParams.unactiveToken][msg.sender] < amount) {
            revert IStoaErrors.InsufficientRedemptionAllowance(amount);
        }

        LibToken._burn(yieldToken, amount, withdrawer, requestUnderlying, 1);
    }

    function rebase(
        address activeToken
    )
    // onlyKepper
    external returns (uint256 yield, uint256 holderYield, uint256 stoaYield) {
        // _onlyWhitelisted();
        // _checkSupportedYieldToken(yieldToken);

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 currentSupply = IERC20(activeToken).totalSupply();
        if (currentSupply == 0) return (0, 0, 0);

        uint256 value = LibToken._totalValue(yieldToken);

        if (value > currentSupply) {

            yield = value - currentSupply;
            if (yield < 10_000) {
                revert IStoaErrors.IllegalRebase(yield);
            }

            holderYield = (yield / 10_000) * (10_000 - s.mgmtFee[activeToken]);
            stoaYield = yield - holderYield;

            IStoaToken(activeToken).changeSupply(currentSupply + holderYield);

            if (stoaYield > 0) {
                IStoaToken(activeToken).mint(address(this), stoaYield);
            }
        }

        s.holderYieldAccrued[activeToken] += holderYield;
        s.stoaYieldAccrued[activeToken] += stoaYield;
    }

    function depositToSafe(
        address yieldToken,
        uint256 amount,
        address venue
    ) external returns (uint256) {

    }

    function depositUnderlyingToSafe(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external returns (uint256) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);


    }
    
}