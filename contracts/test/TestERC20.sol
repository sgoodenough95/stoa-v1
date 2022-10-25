// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {

    constructor(
        string memory _name,
        string memory _symbol,
        uint _genesisMint
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _genesisMint);
    }

    function mint(address _to, uint _amount) external {
        _mint(_to, _amount);
    }
}