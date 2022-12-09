// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    AppStorage,
    RefTokenParams
} from "../../libs/LibAppStorage.sol";
import { LibToken } from "../../libs/LibToken.sol";
import "../../interfaces/IStoa.sol";
import "../../interfaces/IStoaToken.sol";
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

    function disableVault(
        address vaultToken
    ) external {

    }

    function pullUnderlying(
        address vaultToken,
        uint256 amount,
        uint256 minimumAmountOut
    ) external returns (uint256 assets) {
        // Initial checks.

    }

    function onboardToken(
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

            IStoaToken(activeToken).changeSupply(currentSupply + holderYield);

            if (stoaYield > 0) {
                IStoaToken(activeToken).mint(address(this), stoaYield);
            }
        }

        s.holderYieldAccrued[activeToken] += holderYield;
        s.stoaYieldAccrued[activeToken] += stoaYield;
    }

    function adjustFee(
        address activeToken,
        uint8   feeType,
        uint256 newFee
    ) external {

    }
}