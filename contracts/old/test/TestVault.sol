// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Test Vault Contract
 */

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TestERC20 } from "./TestERC20.sol";
import { ITestERC20 } from "./ITestERC20.sol";

contract TestVault is ERC4626 {
    using SafeERC20 for IERC20;

    address inputToken;

    constructor(
        ERC20 underlying_,
        address inputToken_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(underlying_) {
        inputToken = inputToken_;
    }

    function simulateYield(uint _yield) external {

        ITestERC20(inputToken).mint(address(this), _yield);
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
}