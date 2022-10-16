// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title Stoa Treasury Contract
 * @author The Stoa Corporation Ltd.
 * @notice
 *  Collects protocol revenue and engages in market operations
 *  to achieve strategic goals.
 */

import "hardhat/console.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/IUnactivated.sol";
import "./utils/Common.sol";
import "./utils/RebaseOpt.sol";

contract Treasury is Ownable, Common, RebaseOpt {

    mapping(address => mapping(address => int)) backingReserve;

    uint controllerBuffer;

    // Provide approval for Controller spend in constructor.

    function distribute(address _target, address _token, uint _amount)
        external
        onlyOwner
    {

    }

    // Requires knowing targetController of activeTokens.
    function redeemActiveTokens()
        external
    {

    }

    function adjustBackingReserve(address _wildToken, address _backingToken, int _amount)
        external
        // onlyController
    {
        backingReserve[_wildToken][_backingToken] += _amount;
    }
}