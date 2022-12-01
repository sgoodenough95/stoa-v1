// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/// @title  Unactivated Stoa Token Interface
/// @author stoa.money
/// @notice Mint and burn Stoa tokens.
interface IStoaToken {

    function mint(address _to, uint _amount) external;

    function burn(address _from, uint _amount) external;
}