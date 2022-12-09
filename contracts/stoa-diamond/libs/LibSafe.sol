// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/// @dev A Safe supports one activeToken and one debtToken.
struct Safe {
    address owner;
    // Identifier for the Safe.
    uint index;
    // E.g., USDSTa.
    address activeToken;
    // E.g., USDST
    // Might not necessarily know this when opening a Safe.
    address debtToken;
    // activeToken creditBalance;
    uint bal;   // apTokens
    // Balance of the debtToken.
    uint debt;  // tokens = credits
    uint mintFeeApplied;
    uint redemptionFeeApplied;
    uint originationFeesPaid;   // credits
    SafeStatus status;
}

enum SafeStatus {
    nonExistent,
    active,
    closedByOwner,
    closedByLiquidation
}