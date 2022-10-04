// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Test Vault Contract
 */

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TestDAI } from "./TestDAI.sol";
import { ITestDAI } from "./ITestDAI.sol";

contract TestVault is ERC4626 {
    using SafeERC20 for IERC20;

    address testDAI;

    uint tokenBaseUnits = 10 ** 18;

    constructor(
        ERC20 underlying_,
        address testDAI_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(underlying_) {
        testDAI = testDAI_;
    }

    function simulateYield() external {

        ITestDAI(testDAI).mint(address(this), 1_000 * tokenBaseUnits);
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