// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface ISafeManager {

    function getSafeInit(address _owner, uint _index) external view returns (address, address, address);

    function getSafeVal(address _owner, uint _index) external view returns (uint, uint, uint, uint);

    function getSafeStatus(address _owner, uint _index) external view returns (uint);

    function initializeSafe(address _owner, address _activeToken, uint _amount, uint _mintFeeApplied, uint _redemptionFeeApplied) external;

    function adjustSafeBal(
        address _owner,
        uint _index,
        address _activeToken,
        uint _amount,
        bool _add,
        uint _mintFeeApplied,
        uint _redemptionFeeApplied
    ) external;

    function adjustSafeDebt(
        address _owner,
        uint _index,
        address _debtToken,
        uint _amount,
        bool _add
    ) external;

    function setSafeStatus(
        address _owner,
        uint _index,
        address _activeToken,
        uint _num
    ) external;

    function initializeBorrow(
        address _owner,
        uint _index,
        // address _activeToken,
        // uint _toLock,
        address _debtToken
        // uint _amount,
        // uint _fee
    ) external;

    function getActiveToDebtTokenMCR(address _activeToken, address _debtToken) external view returns (uint _MCR);

    function getUnactiveCounterpart(address _activeToken) external view returns (address unactiveToken);

    function getActivePool(address _token) external view returns (address activePool);
}