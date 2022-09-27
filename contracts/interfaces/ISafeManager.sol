// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface ISafeManager {

    // Later import
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation
    }

    // One Safe supports one type of receiptToken and one type of debtToken.
    struct Safe {
        // // E.g., USDST
        address receiptToken;
        // E.g., USDSTu
        // Might not necessarily know this when opening a Safe.
        address debtToken;
        // receiptToken creditBalance;
        uint bal;
        // Increments only if depositing activeToken.
        uint mintFeeApplied;
        uint redemptionFeeApplied;
        // Balance of the debtToken.
        uint debt;
        // Amount of receiptTokens locked as collateral.
        uint locked;
        uint index;
        Status status;
    }

    function getSafe(
        address _owner,
        uint _index
    ) external view returns (address, address, address, uint, uint, uint, uint, uint, uint);

    function openSafe(
        address _owner,
        address _receiptToken,
        uint _amount,
        uint _mintFeeApplied,
        uint _redemptionFeeApplied
    ) external;

    function adjustSafeBal(
        address _owner,
        uint _index,
        address _receiptToken,
        uint _amount,
        bool _add,
        uint _mintFeeApplied,
        uint _redemptionFeeApplied
    ) external;

    function updateRebasingCreditsPerToken(address _inputToken) external view returns (uint);
}