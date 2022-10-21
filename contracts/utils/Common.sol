// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

contract Common {

    address public safeOperations;

    modifier onlySafeOps()
    {
        require(msg.sender == safeOperations, "SafeManager: Only SafeOps can call");
        _;
    }

    function setSafeOps(address _safeOperations)
        external
    {
        safeOperations = _safeOperations;
    }
}