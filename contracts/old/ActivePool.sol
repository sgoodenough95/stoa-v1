// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title wUSDSTa Token Contract
 * @dev ERC4626 that issues wUSDSTa as its share token.
 * @author Origin Protocol Inc & The Stoa Corporation Ltd.
 * @notice
 *  Forked from
 *  https://github.com/OriginProtocol/origin-dollar/blob/master/contracts/contracts/token/WrappedOusd.sol
 *  Additional methods added for Stability Pool transfers.
 * @dev
 *  Imports for Initializable and Governable removed at least for now.
 */

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import { Governable } from "../governance/Governable.sol";
// import { Initializable } from "../utils/Initializable.sol";
import { OldActivatedToken } from "./token/OldActivatedToken.sol";

contract ActivePool is ERC4626 {
    using SafeERC20 for IERC20;

    constructor(
        ERC20 underlying_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(underlying_) {}

    /**
     * @notice Enable rebasing for this contract
     */
    // function initialize() external onlyGovernor initializer {
    //     OUSD(address(asset())).rebaseOptIn();
    // }

    function rebaseOptIn() public {
        OldActivatedToken(address(asset())).rebaseOptIn();
    }

    function rebaseOptOut() public {
        OldActivatedToken(address(asset())).rebaseOptOut();
    }

    /**
     * @dev Added additional argument: depositor.
     */
    function deposit(uint256 assets, address receiver, address depositor)
        public
        returns (uint256 shares)
    {
        // Amended for OZ ERC4626. VaultWrapper has different implementation.
        shares = previewDeposit(assets);
        _deposit(depositor, receiver, assets, shares);

        emit Deposit(depositor, receiver, assets, shares);
    }

    // function name() public view override returns (string memory) {
    //     return "Wrapped OUSD";
    // }

    // function symbol() public view override returns (string memory) {
    //     return "WOUSD";
    // }

    /**
     * @notice Transfer token to governor. Intended for recovering tokens stuck in
     *      contract, i.e. mistaken sends. Cannot transfer OUSD
     * @param asset_ Address for the asset
     * @param amount_ Amount of the asset to transfer
     */
    // function transferToken(address asset_, uint256 amount_)
    //     external
    //     onlyGovernor
    // {
    //     require(asset_ != address(asset()), "Cannot collect OUSD");
    //     IERC20(asset_).safeTransfer(governor(), amount_);
    // }
}