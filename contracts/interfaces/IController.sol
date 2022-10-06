// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/**
 * @title Stoa Controller Interface
 * @author stoa.money
 * @notice
 *  Interface that provides functions for interacting with respective Controller contract.
 *  Each asset type has a dedicated Controller contract.
 *  These include (but may not be limited to):
 *  - Stable Controller (dedicated to USD-pegged stablecoins).
 *  - ETH Controller.
 *  - Tokenn Controller (generalised for standard ERC20s, e.g. WBTC, LINK, etc.).
 */
interface IController {

    function deposit(address _depositor, uint _amount, bool _activated) external returns (uint mintAmount);

    function withdrawTokensFromSafe(address _withdrawer, bool _activated, uint _amount, int _feeCoverage) external returns (uint amount);

    function getActiveToken() external view returns (address _activeToken);

    function getInputToken() external view returns (address _inputToken);
}