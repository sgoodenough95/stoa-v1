// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AppStorage,
    UnderlyingTokenParams,
    YieldTokenParams,
    StoaTokenParams,
    ActivePoolTokenParams
} from ".././libs/LibAppStorage.sol";
import { LibToken } from ".././libs/LibToken.sol";
import ".././interfaces/IStoa.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  ControllerFacet
/// @author The Stoa Corporation Ltd.
/// @notice User-facing functions for 
contract ControllerFacet {

    AppStorage internal s;

    /// @notice Non-custodial deposit of vault token (e.g., yvDAI).
    function deposit(
        address yieldToken,
        uint256 shares,
        address depositor,  // msg.sender (?)
        // address recipient,
        uint8   activeToken
    ) external returns (uint256 stoaTokens) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        if (shares >= s.minDeposit[yieldToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }
        if (activeToken >= 2) {
            revert IStoaErrors.IllegalArgument(5);
        }

        LibToken._ensureEnabled(yieldToken);

        SafeERC20.safeTransferFrom(IERC20(yieldToken), msg.sender, address(this), shares);

        stoaTokens = LibToken._mint(yieldToken, shares, depositor, activeToken);
    }

    /// @notice Non-custodial deposit of underlyingToken (e.g., DAI).
    function depositUnderlying(
        address yieldToken,
        uint256 amount,
        address depositor,  // msg.sender (?)
        // address recipient,
        uint8 activeToken
    ) external returns (uint256 stoaTokens) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        if (amount >= s.minDeposit[yieldToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        LibToken._ensureEnabled(yieldToken);

        // Before depositing, the underlying tokens must be wrapped into yield tokens.
        uint256 shares = LibToken._wrap(yieldToken, amount, depositor);

        stoaTokens = LibToken._mint(yieldToken, shares, depositor, activeToken);
    }

    /// @notice Withdrawal of vault tokens (e.g., yvDAI).
    function withdraw(
        address yieldToken,
        uint256 amount,  // the amount of active tokens.
        address withdrawer  // msg.sender (?)
        // address recipient
    ) external returns (uint256 shares) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        if (amount >= s.minDeposit[yieldToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];

        // first, transfer active tokens to Stoa.
        SafeERC20.safeTransferFrom(IERC20(yieldTokenParams.activeToken), msg.sender, address(this), amount);

        shares = LibToken._burn(yieldToken, amount, withdrawer, 0, 0);

        // transfer vault tokens to user.
        SafeERC20.safeTransfer(IERC20(yieldToken), withdrawer, shares);
    }

    /// @notice Withdrawal of underlying tokens (e.g., DAI).
    function withdrawUnderlying(
        address yieldToken,
        uint256 amount,
        address withdrawer
    ) external returns (uint256 shares) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        if (amount >= s.minDeposit[yieldToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];

        SafeERC20.safeTransferFrom(IERC20(yieldTokenParams.activeToken), msg.sender, address(this), amount);

        shares = LibToken._burn(yieldToken, amount, withdrawer, 1, 0);
    }

    function unactiveRedemption(
        address yieldToken,
        uint256 amount,
        address withdrawer,
        uint8   underlyingToken
    ) external returns (uint256 shares) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);
        if (amount >= s.minDeposit[yieldToken]) {
            revert IStoaErrors.IllegalArgument(1);
        }

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];

        if (s.unactiveRedemptionAllowance[yieldTokenParams.unactiveToken][withdrawer] < amount) {
            revert IStoaErrors.IllegalArgument(1);
        }

        shares = LibToken._burn(yieldToken, amount, withdrawer, underlyingToken, 1);
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