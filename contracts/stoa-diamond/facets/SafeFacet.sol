// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import {
    AppStorage,
    RefTokenParams
} from "./../libs/LibAppStorage.sol";
import { LibToken } from "./../libs/LibToken.sol";
import "./../interfaces/IStoa.sol";
import "./../interfaces/IStoaToken.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title  SafeFacet
/// @author The Stoa Corporation Ltd.
/// @notice User-facing functions for managing Safes.
contract SafeFacet {
    AppStorage internal s;

    function openWithUnderlying(
        address activeToken,
        uint256 amount,
        uint256 minAmountOut,
        address depositFrom
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

        // Transfer activeTokens to the respective safeStore contract.
        activeAmount = LibToken._mintActiveFromVault(activeToken, shares, refTokenParams.safeStore);

        
    }

    function openWithVault(
        address activeToken,
        uint256 amount
    ) external {

    }

    function openWithActive(
        address activeToken,
        uint256 amount
    ) external {

    }

    function depositUnderlying(
        uint256 index,
        address activeToken,
        uint256 amount
    ) external {

    }

    function depositVault(
        uint256 index,
        address activeToken,
        uint256 amount
    ) external {
        
    }

    function depositActive(
        uint256 index,
        address activeToken,
        uint256 amount
    ) external {
        
    }

    function withdrawUnderlying(
        uint256 index,
        address activeToken,
        uint256 amount
    ) external {
        
    }

    function withdrawVault(
        uint256 index,
        address activeToken,
        uint256 amount
    ) external {
        
    }

    function withdrawActive(
        uint256 index,
        address activeToken,
        uint256 amount
    ) external {
        
    }
    
}