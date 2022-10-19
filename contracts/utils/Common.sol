// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

contract Common {

    address public safeOperations;

    mapping(address => address) public tokenToAP;

    modifier onlySafeOps()
    {
        require(msg.sender == safeOperations, "SafeManager: Only SafeOps can call");
        _;
    }

    function setActivePool(address _token, address _activePool)
        external
    {
        tokenToAP[_token] = _activePool;
    }

    function setSafeOps(address _safeOperations)
        external
    {
        safeOperations = _safeOperations;
    }
}