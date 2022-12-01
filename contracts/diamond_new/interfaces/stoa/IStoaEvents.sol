// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title  IStoaEvents
/// @author The Stoa Corporation Ltd.

interface IStoaEvents {
    /// @notice Emitted when a user deposits `amount of `yieldToken` to `recipient`.
    ///
    /// @notice This event does not imply that `sender` directly deposited yield tokens. It is possible that the
    ///         underlying tokens were wrapped.
    ///
    /// @param sender       The address of the user which deposited funds.
    /// @param yieldToken   The address of the yield token that was deposited.
    /// @param amount       The amount of yield tokens that were deposited.
    /// @param recipient    The address that received the deposited funds.
    event Deposit(address indexed sender, address indexed yieldToken, uint256 amount, address recipient);

    event Mint(address indexed depositor, address indexed stoaToken, uint256 amount);

    event SafeOpened();

}