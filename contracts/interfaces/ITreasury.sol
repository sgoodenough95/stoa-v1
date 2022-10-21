// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface ITreasury {

    function adjustAPTokenBal(address _activePool, uint _amount) external;

    function adjustBackingReserve(address _wildToken, address _backingToken, int _amount) external;
}