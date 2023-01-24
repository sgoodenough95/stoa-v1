// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AppStorage,
    RefTokenParams,
    UnderlyingTokenParams,
    VaultTokenParams
} from "./../libs/LibAppStorage.sol";
import { LibToken } from "./../libs/LibToken.sol";
import "./../interfaces/IStoa.sol";
import "./../interfaces/IStoaToken.sol";
import "./../interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AdminFacet {
    AppStorage internal s;

    /// @notice Migration to new vault that accepts same underlyingToken.
    function migrateToLikeVault(
        address activeToken,
        address vault,
        uint256 amount, // if > maxWithdraw: amount = maxWithdraw.
        uint256 buffer, // To ensure successful exec. of rebase() upon migration.
        uint256 minimumAmountOut
    ) external {
        // 1. Disable user-facing functions to vault.
        // 2. Redeem funds from vault.
        // 3. Deploy funds + buffer to new vault.
        // 4. Rebase to synchronise.
        // 5. Enable functions.

        // May be split into separate fns + via script.

        uint8 enabled = LibToken._toggleEnabledActiveToken(activeToken);
        if (enabled != 0) {
            revert IStoaErrors.TokenDisabled(activeToken);
        }

        this.pullUnderlyingFromVault(
            s._refTokens[activeToken].vaultToken,
            amount,
            minimumAmountOut
        );

        this.deployUnderlyingToVault(vault, amount + buffer);

        // Update refTokenParams
        this.updateRefToken(
            activeToken,
            IERC4626(vault).asset(),
            vault,
            s._refTokens[activeToken].unactiveToken,
            s._refTokens[activeToken].depositLimit
        );

        // Rebase
        this.rebase(activeToken);

        enabled = LibToken._toggleEnabledActiveToken(activeToken);
        if (enabled != 1) {
            revert IStoaErrors.TokenDisabled(activeToken);
        }
    }

    /// @notice Migration to new vault that does not accept same underlyingToken.
    ///
    /// @notice New underlyingToken should be of the same denomination.
    ///         E.g., DAI -> USDC.
    function migrateToUnlikeVault(
        address activeToken,
        address vault,
        address router,
        uint256 amount,
        uint256 buffer,
        uint256 minimumAmountOut
    ) external {
        // 1. Disable user-facing functions to vault.
        // 2. Redeem funds from vault.
        // 3. Exchange for new underlyingToken.
        // 4. Deploy exchanged funds + buffer to new vault.
        // 5. Rebase to synchronise.
        // 6. Enable functions.

        // May be split into separate fns + via script.
    }

    /// @notice Pulls underlying without burning Stoa tokens.
    function pullUnderlyingFromVault(
        address vaultToken,
        uint256 amount,
        uint256 minimumAmountOut
    )   external
        //onlyAdmin
        returns (uint256 assets) {
        // Initial checks.

        uint256 _amount = amount > IERC20(vaultToken).balanceOf(address(this))
            ? IERC20(vaultToken).balanceOf(address(this))
            : amount;

        assets = IERC4626(vaultToken).redeem(_amount, address(this), address(this));
        if (assets < minimumAmountOut) {
            revert IStoaErrors.MaxSlippageExceeded(assets, minimumAmountOut);
        }
    }

    function deployUnderlyingToVault(
        address vaultToken,
        uint256 amount
    )   external
        // onlyAdmin
        returns (uint256 shares) {
        
        shares = IERC4626(vaultToken).deposit(amount, address(this));
    }

    function updateRefToken(
        address activeToken,
        address underlyingToken,
        address vaultToken,
        address unactiveToken,
        uint256 depositLimit
    ) external {

        RefTokenParams storage refTokenParams = s._refTokens[activeToken];

        refTokenParams.underlyingToken  = underlyingToken;
        refTokenParams.vaultToken       = vaultToken;
        refTokenParams.unactiveToken    = unactiveToken;
        refTokenParams.depositLimit     = depositLimit;
        refTokenParams.enabled          = 1;
    }

    // function enableToken(
    //     address token,
    //     uint8   tokenType
    // ) external {

    //     if (tokenType == 0) {
    //         UnderlyingTokenParams storage underlyingTokenParams = s._underlyingTokens[token];
    //         underlyingTokenParams.enabled = 1;
    //     } else if (tokenType == 1) {
    //         VaultTokenParams storage vaultTokenParams = s._vaultTokens[token];
    //         vaultTokenParams.enabled = 1;
    //     }   // Remaining args not needed right now.
    // }

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

        uint256 value = LibToken._totalValue(refTokenParams.vaultToken);

        if (value > currentSupply) {

            yield = value - currentSupply;
            if (yield < 10_000) {
                revert IStoaErrors.IllegalRebase(yield);
            }

            holderYield = (yield / 10_000) * (10_000 - s.mgmtFee[activeToken]);
            stoaYield = yield - holderYield;

            // NB: Later replace with drip operation to smooth out yield.
            IStoaToken(activeToken).changeSupply(currentSupply + holderYield);

            if (stoaYield > 0) {
                IStoaToken(activeToken).mint(address(this), stoaYield);
            }
        }

        s.holderYieldAccrued[activeToken] += holderYield;
        s.stoaYieldAccrued[activeToken] += stoaYield;
    }

    function adjustFee(
        address token,
        uint256 fee,    // Basis points.
        uint8   feeType
    ) external {

        if (feeType == 1) {
            s.mintFee[token] = fee;
        } else if (feeType == 2) {
            s.redemptionFee[token] = fee;
        } else if (feeType == 3) {
            s.conversionFee[token] = 4;
        }   // Remaining args not needed right now.
    }

    function adjustMinTx(
        address token,
        uint256 minTx,
        uint8   txType
    ) external {

        if (txType == 0) {
            s.minDeposit[token] = minTx;
        } else if (txType == 1) {
            s.minWithdraw[token] = minTx;
        }   // Remaining args not needed right now.
    }
}