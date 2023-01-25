// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {
    AppStorage,
    RefTokenParams,
    LibAppStorage
} from "./LibAppStorage.sol";
import { LibTreasury } from "./LibTreasury.sol";
import { IERC4626 } from ".././interfaces/IERC4626.sol";
import ".././interfaces/IStoa.sol";
import ".././interfaces/IStoaToken.sol";

/// @title  LibSafe
/// @author The Stoa Corporation Ltd.
/// @notice Internal functions for managing Safes.
library LibSafe {

    /// @dev    May later move to AppStorage.
    uint256 constant BPS = 10_000;

    /// @notice Initializes a Safe instance.
    ///
    /// @dev    Mint/redemption fees to come later.
    function _initializeSafe(
        address owner,
        address activeToken,
        uint256 amount
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 index = s.currentSafeIndex[owner];

        s.safe[owner][index].owner          = owner;
        s.safe[owner][index].activeToken    = activeToken;
        s.safe[owner][index].bal            = amount;
        s.safe[owner][index].index          = index;
        s.safe[owner][index].status         = 1;

        s.currentSafeIndex[owner] += 1;
    }

    function _initializeDebt(
        address owner,
        uint256 index,
        uint256 amount
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (s.safe[owner][index].status != 1) {
            revert IStoaErrors.SafeNotActive(owner, index);
        }

        address activeToken = s.safe[owner][index].activeToken;

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        s.safe[owner][index].debtToken  = refTokenParams.unactiveToken;
        s.safe[owner][index].debt       = amount;
        s.safe[owner][index].status     = 2;
    }

    function _adjustSafeBal(
        address owner,
        uint256 index,
        int256  amount
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 _amount = LibAppStorage.abs(amount);

        if (s.safe[owner][index].status != 1 || s.safe[owner][index].status != 2) {
            revert IStoaErrors.SafeNotActive(owner, index);
        }
        // Does not account for an event where amount = 0, as this will never execute.
        if (amount > 0) {
            s.safe[owner][index].bal += _amount;
        } else {
            if (_amount > s.safe[owner][index].bal) {
                revert IStoaErrors.InsufficientSafeBal(owner, index);
            }
            s.safe[owner][index].bal -= _amount;
        }
    }

    function _adjustSafeDebt(
        address owner,
        uint256 index,
        int256  amount
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 _amount = LibAppStorage.abs(amount);

        if (s.safe[owner][index].status != 1 || s.safe[owner][index].status != 2) {
            revert IStoaErrors.SafeNotActive(owner, index);
        }
        // If increasing debt (i.e., borrowing).
        if (amount > 0) {
            s.safe[owner][index].debt += _amount;
        } else {
            // If paying off debt.
            /// @dev Allow for if repayment amount exceeds debt. Ensure to only transfer required tokens.
            if (_amount >= s.safe[owner][index].debt) {
                s.safe[owner][index].debt       = 0;
                s.safe[owner][index].debtToken  = address(0);
            } else {
                // If only reducing debt.
                s.safe[owner][index].debt -= _amount;
            }
        }
    }

    function _adjustSafeStatus(
        address owner,
        uint256 index,
        uint8   status
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        s.safe[owner][index].status = status;
    }

    function _closeSafe(
        address owner,
        uint256 index,
        uint8   closedBy
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (s.safe[owner][index].status != 1 || s.safe[owner][index].status != 2) {
            revert IStoaErrors.SafeNotActive(owner, index);
        }

        /// @dev Only change the status for now.
        s.safe[owner][index].status = closedBy;
    }

    /// @dev    Returns the free amount of activeTokens (not Safe shares).
    function _getWithdrawAllowance(
        address owner,
        uint256 index
    ) internal view returns (uint256 locked, uint256 free) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (s.safe[owner][index].status != 1 || s.safe[owner][index].status != 2) {
            revert IStoaErrors.SafeNotActive(owner, index);
        }
        if (s.safe[owner][index].status == 1) {
            return (0, s.safe[owner][index].bal);
        }

        address activeToken = s.safe[owner][index].activeToken;

        // Calc the amount locked given the debt and CR.
        locked = s.safe[owner][index].debt
            * s.CR[activeToken][s.safe[owner][index].debtToken] / BPS;

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        // Need to retrieve the amount of activeTokens from ther user's share tokens.
        uint256 activeAmount =
            IERC4626(refTokenParams.safeStore).previewRedeem(s.safe[owner][index].bal);

        if (locked >= activeAmount) {
            return (locked, 0);
        }
        return (locked, activeAmount - locked);
    }
}