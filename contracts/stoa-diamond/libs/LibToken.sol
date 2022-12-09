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

        shares = vault.deposit(amount, address(this), depositFrom);
    }

    function _mintActiveFromVault(
        address activeToken,
        uint256 shares,
        address recipient
    ) internal returns (uint256 stoaTokens) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        stoaTokens = vault.previewRedeem(shares);

        uint256 mintFee         = _computeFee(
            activeToken,
            stoaTokens,
            1
        );
        uint256 mintAfterFee    = stoaTokens - mintFee;

        // Stoa captures mintFee amount of activeTokens if available.
        if (mintFee > 0) {
            IStoaToken(activeToken).mint(address(this), mintFee);
        }
        IStoaToken(activeToken).mint(recipient, mintAfterFee);
    }

    function _mintUnactiveFromVault(
        address activeToken,
        uint256 shares,
        address recipient
    ) internal returns (uint256 stoaTokens) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        stoaTokens = vault.previewRedeem(shares);

        uint256 mintFee         = _computeFee(
            activeToken,
            stoaTokens,
            1
        );
        uint256 mintAfterFee    = stoaTokens - mintFee;

        // First, mint activeTokens to Stoa to serve as backing.
        IStoaToken(activeToken).mint(address(this), stoaTokens);

        // Update backing reserve. Stoa captures mintFee amount of activeTokens.
        LibTreasury._adjustBackingReserve(
            refTokenParams.unactiveToken,
            activeToken,
            int(mintAfterFee)
        );

        IStoaToken(refTokenParams.unactiveToken).mint(recipient, mintAfterFee);

        // Update unactive redemption allowance for caller.
        s._unactiveRedemptions[msg.sender][activeToken] += mintAfterFee;
    }

    function _mintUnactive(
        address activeToken,
        uint256 amount,
        address recipient,
        uint8   feeType
    ) internal returns (uint256 mintAfterFee) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 fee     = _computeFee(
            refTokenParams.unactiveToken,
            amount,
            feeType
        );
        mintAfterFee  = amount - fee;

        IStoaToken(refTokenParams.unactiveToken).mint(recipient, mintAfterFee);
    }

    function _mintUnactiveDetailed(
        address activeToken,
        uint256 amount,
        address recipient,
        uint8   feeType,
        uint8   updateBacking,
        uint8   updateAllowance
    ) internal returns (uint256 mintAfterFee) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        uint256 fee     = _computeFee(
            refTokenParams.unactiveToken,
            amount,
            feeType
        );
        mintAfterFee  = amount - fee;

        if (updateBacking == 1) {
            LibTreasury._adjustBackingReserve(
            refTokenParams.unactiveToken,
            activeToken,
            int(mintAfterFee)
            );
        }

        IStoaToken(refTokenParams.unactiveToken).mint(recipient, mintAfterFee);

        if (updateAllowance == 1) {
            s._unactiveRedemptions[msg.sender][activeToken] += mintAfterFee;
        }
    }

    function _burnActive(
        address activeToken,
        uint256 amount,
        address recipient,  // Only if requesting underlyingToken.
        uint8   feeType
    ) internal returns (uint256 shares) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        uint256 fee       = _computeFee(
            activeToken,
            amount,
            feeType
        );
        uint256 burnAfterFee  = amount - fee;

        // Stoa captures fee amount of activeTokens.
        IStoaToken(activeToken).burn(address(this), burnAfterFee);

        shares = vault.convertToShares(burnAfterFee);

        if (recipient != address(0)) {
            vault.redeem(shares, recipient, address(this));
        }
    }

    function _burnUnactive(
        address activeToken,
        uint256 amount,
        address withdrawFrom,
        address recipient,  // Only if requesting underlyingToken.
        uint8   feeType
    ) internal returns (uint256 shares, uint256 burnAfterFee) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        RefTokenParams memory refTokenParams = s._refTokens[activeToken];

        IERC4626 vault = IERC4626(refTokenParams.vaultToken);

        uint256 fee       = _computeFee(
            refTokenParams.unactiveToken,
            amount,
            feeType
        );
        burnAfterFee  = amount - fee;

        IStoaToken(activeToken).burn(withdrawFrom, amount);

        s._unactiveRedemptions[msg.sender][activeToken] -= burnAfterFee;

        shares = vault.convertToShares(burnAfterFee);

        if (recipient != address(0)) {
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

        uint256 _fee;
        // Lookup fee table.
        if (feeType == 0) {
            // No fee.
            return 0;
        } else if (feeType == 1) {
            _fee = s.mintFee[activeToken];
        } else if (feeType == 2) {
            _fee = s.redemptionFee[activeToken];
        } else if (feeType == 3) {
            _fee = s.conversionFee[activeToken];
        } else if (feeType == 4) {
            // NB: May be according to some fee table.
            _fee = s.originationFee[activeToken];
        } else if (feeType == 5) {
            _fee = s.mgmtFee[activeToken];
        } else {
            revert IStoaErrors.IllegalArgument(2);
        }

        if (_fee == 0) return 0;
        
        // NB: Need to double check secure operation - may require library/scalor.
        fee = amount / BPS * _fee;
    }
}