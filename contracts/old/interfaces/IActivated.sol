// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/**
 * @title Activated Stoa Token Interface
 * @author stoa.money
 * @notice
 *  Interface that provides functions for interacting with activated Stoa tokens.
 */
interface IActivated {

    function mint(address _account, uint _amount) external;

    function burn(address _account, uint _amount) external;

    function transfer(address _to, uint256 _value) external returns (bool);

    function transferFrom(address _from, address _to, uint _value) external returns (bool);

    function convertToAssets(uint _creditBalance) external view returns (uint);

    function convertToCredits(uint _tokenBalance) external view returns (uint);
    
    function changeSupply(uint _newTotalSupply) external;

    function rebaseOptIn() external;

    function rebaseOptOut() external;

    function rebasingCreditsPerToken() external view returns (uint);
}