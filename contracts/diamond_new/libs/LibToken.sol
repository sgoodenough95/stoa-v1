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

library LibToken {

    uint256 constant BPS = 10_000;

    function _wrap(
        address activeToken,
        uint256 amount,
        address depositFrom
    ) internal returns (uint256 shares) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        shares = vault.deposit(amount, address(this), depositor);
    }

    function _mint(
        address activeToken,
        uint256 shares,
        address recipient,
        uint8   activated
    ) internal returns (uint256 stoaTokens) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        stoaTokens = vault.previewRedeem(shares);

        uint256 mintFee         = _computeFee(
            yieldTokenParams.activeToken,
            stoaTokens,
            0
        );
        uint256 mintAfterFee    = stoaTokens - mintFee;

        if (activated == 0) {
            IStoaToken(activeToken).mint(address(this), stoaTokens);

            LibTreasury._adjustBackingReserve(
                refTokenParams.unactiveToken,
                activeToken,
                int(mintAfterFee)
            );

            IStoaToken(refTokenParams.unactiveToken).mint(recipient, mintAfterFee);

            // Increment redemption allowance for msg.sender (may or may not be recipient).
            s.unactiveRedemptionAllowance[refTokenParams.unactiveToken][msg.sender]
                += mintAfterFee;
        } else if (activated == 1) {
            if (mintFee > 0) {
                IStoaToken(activeToken).mint(address(this), mintFee);
            }
            IStoaToken(activeToken).mint(recipient, mintAfterFee);
        }
    }

    function _burn(
        address activeToken,
        uint256 amount,
        address recipient,  // Only read when requesting underlyingToken.
        uint8   requestUnderlying,
        uint8   inputUnactive
    ) internal returns (uint256 shares) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        uint256 redemptionFee       = _computeFee(
            activeToken,
            amount,
            1
        );
        uint256 redemptionAfterFee  = amount - redemptionFee;

        // Do not apply a fee if converting from unactiveToken to activeToken.
        // Only callable via unactiveRedemption().
        if (inputUnactive == 1) {
            IStoaToken(activeToken).burn(address(this), amount);
            s.unactiveRedemptionAllowance[refTokenParams.unactiveToken][msg.sender]
                -= amount;
        } else {
            IStoaToken(activeToken).burn(address(this), redemptionAfterFee);
        }

        shares = vault.convertToShares(amount);

        if (requestUnderlying == 1) {
            vault.redeem(shares, recipient, address(this));
        }
    }

    function _ensureEnabled(
        address activeToken
    ) internal view returns (uint8) {

        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        _checkVaultTokenEnabled(refTokenParams.vaultToken);
        _checkUnderlyingTokenEnabled(refTokenParams.underlyingToken);

        // _checkLoss(yieldToken);
        return 1;
    }

    function _checkVaultTokenEnabled(address vaultToken) internal view {
        AppStorage storage s = LibAppStorage.diamondStorage();
        if (s._vaultTokens[vaultToken].enabled != 1) {
            revert IStoaErrors.TokenDisabled(vaultToken);
        }
    }

    function _checkUnderlyingTokenEnabled(address underlyingToken) internal view {
        AppStorage storage s = LibAppStorage.diamondStorage();
        if (s._underlyingTokens[underlyingToken].enabled != 1) {
            revert IStoaErrors.TokenDisabled(underlyingToken);
        }
    }

    function _rebaseOptIn(
        address activeToken
    ) internal {
        IStoaToken(activeToken).rebaseOptIn();
    }

    function _rebaseOptOut(
        address activeToken
    ) internal {
        IStoaToken(activeToken).rebaseOptOut();
    }

    function _totalValue(
        address vaultToken
    ) internal view returns (uint256 value) {
        // initialized (?)

        value = IERC4626(vaultToken).maxWithdraw(address(this));
    }

    function _previewRedeem(
        address vaultToken,
        uint256 shares
    ) internal view returns (uint256 assets) {
        // initialized (?)

        assets = IERC4626(vaultToken).previewRedeem(shares);
    }

    function _computeFee(
        address activeToken,
        uint256 amount,
        uint8   feeType
    ) internal view returns (uint256 fee) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 _fee = feeType == 0
            ? s.mintFee[activeToken]
            : s.redemptionFee[activeToken];

        if (_fee == 0) return amount;
        
        // need to double check - use library or scalor.
        fee = amount / BPS * _fee;
    }
}