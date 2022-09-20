// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/**
 * @title Unactivated Stoa Token Interface
 * @author stoa.money
 * @notice
 *  Interface that provides functions for interacting with unactivated Stoa tokens.
 */
interface IUnactivated {

    function mint(address _account, uint _amount) external;

    function burn(address _account, uint _amount) external;
}