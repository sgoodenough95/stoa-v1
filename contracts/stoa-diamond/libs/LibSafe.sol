// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/// @dev A Safe supports one activeToken and one unactiveToken.
struct Safe {
    address owner;
    uint index;                     // Identifier for the Safe.
    address activeToken;            // E.g., USDSTA.
    // Might not necessarily know this when opening a Safe.
    address debtToken;              // E.g., USDST.
    uint bal;                       // [vaultTokens].
    uint debt;                      // [tokens].
    uint mintFeeApplied;            // [credits].
    uint redemptionFeeApplied;      // [tokens],
    uint originationFeesPaid;       // [credits].
    SafeStatus status;
}

enum SafeStatus {
    nonExistent,
    active,
    closedByOwner,
    closedByLiquidation
}