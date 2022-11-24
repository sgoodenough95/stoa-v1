// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title  ControllerFacet
/// @author The Stoa Corporation Ltd.
/// @notice User-facing functions for 
contract ControllerFacet {

    function deposit(
        address yieldToken,
        uint256 amount,
        address venue
    ) external returns (uint256) {

    }

    function depositUnderlying(
        address yieldToken,
        uint256 amount,
        address venue
    ) external returns (uint256) {
        
    }

    function depositToSafe(
        address yieldToken,
        uint256 amount,
        address venue
    ) external returns (uint256) {

    }

    function depositUnderlyingToSafe(
        address yieldToken,
        uint256 amount,
        address recipient,
        uint256 minimumAmountOut
    ) external returns (uint256) {
        // _onlyWhitelisted();
        // _checkArgument(recipient != address(0));
        // _checkSupportedYieldToken(yieldToken);


    }
    
}