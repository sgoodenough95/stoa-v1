// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {
    AppStorage,
    YieldTokenParams,
    LibAppStorage
} from "./LibAppStorage.sol";
import { LibTreasury } from "./LibTreasury.sol";
import { IERC4626 } from ".././interfaces/IERC4626.sol";
import ".././interfaces/IStoa.sol";
import ".././interfaces/IStoaToken.sol";

library LibToken {

    uint256 constant BPS = 10_000;

    function _wrap(
        address yieldToken,
        uint256 amount,
        address depositor
        // uint256 minimumAmountOut
    ) internal returns (uint256 shares) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];

        IERC4626 yieldVenue = IERC4626(yieldTokenParams.yieldVenue);

        shares = yieldVenue.deposit(amount, address(this), depositor);
    }

    function _mint(
        address yieldToken,
        uint256 shares,
        address depositor,  // msg.sender (?)
        uint8   activeToken // gas overhead (?)
    ) internal returns (uint256 tokens) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];

        IERC4626 yieldVenue = IERC4626(yieldTokenParams.yieldVenue);

        tokens = yieldVenue.previewRedeem(shares);

        uint256 mintFee         = _computeFee(
            yieldTokenParams.activeToken,
            tokens,
            0
        );
        uint256 mintAfterFee    = tokens - mintFee;

        if (activeToken == 0) {
            IStoaToken(yieldTokenParams.activeToken).mint(address(this), tokens);

            LibTreasury._adjustBackingReserve(
                yieldTokenParams.unactiveToken,
                yieldTokenParams.activeToken,
                int(mintAfterFee)
            );

            IStoaToken(yieldTokenParams.unactiveToken).mint(depositor, mintAfterFee);

            s.unactiveRedemptionAllowance[yieldTokenParams.unactiveToken][depositor]
                += mintAfterFee;
        } else if (activeToken == 1) {
            if (mintFee > 0) {
                IStoaToken(yieldTokenParams.activeToken).mint(address(this), mintFee);
            }
            IStoaToken(yieldTokenParams.activeToken).mint(depositor, mintAfterFee);
        }
    }

    function _burn(
        address yieldToken,
        uint256 amount,
        address withdrawer, // msg.sender (?)
        uint8   underlyingToken,
        uint8   unactiveInput
    ) internal returns (uint256 shares) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];

        IERC4626 yieldVenue = IERC4626(yieldTokenParams.yieldVenue);

        uint256 redemptionFee       = _computeFee(
            yieldTokenParams.activeToken,
            amount,
            1
        );
        uint256 redemptionAfterFee  = amount - redemptionFee;

        if (unactiveInput == 1) {
            IStoaToken(yieldTokenParams.activeToken).burn(address(this), amount);
        } else {
            IStoaToken(yieldTokenParams.activeToken).burn(address(this), redemptionAfterFee);
        }

        shares = yieldVenue.convertToShares(amount);

        if (underlyingToken == 1) {
            yieldVenue.redeem(shares, withdrawer, address(this));
        }
    }

    function _ensureEnabled(
        address yieldToken
    ) internal view returns (uint8) {

        AppStorage storage s = LibAppStorage.diamondStorage();

        YieldTokenParams memory yieldTokenParams = s._yieldTokens[yieldToken];
        address underlyingToken = yieldTokenParams.underlyingToken;

        _checkYieldTokenEnabled(yieldToken);
        _checkUnderlyingTokenEnabled(underlyingToken);

        // _checkLoss(yieldToken);
        return 1;
    }

    function _checkYieldTokenEnabled(address yieldToken) internal view {
        AppStorage storage s = LibAppStorage.diamondStorage();
        if (s._yieldTokens[yieldToken].enabled != 1) {
            revert IStoaErrors.TokenDisabled(yieldToken);
        }
    }

    function _checkUnderlyingTokenEnabled(address underlyingToken) internal view {
        AppStorage storage s = LibAppStorage.diamondStorage();
        if (s._yieldTokens[underlyingToken].enabled != 1) {
            revert IStoaErrors.TokenDisabled(underlyingToken);
        }
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