// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestDAI is ERC20 {
    
    uint tokenBaseUnits = 10 ** 18;

    constructor() ERC20("Test DAI", "tDAI") {
        _mint(msg.sender, 10_000 * tokenBaseUnits);
    }

    function mint(address _to, uint _amount) external {
        _mint(_to, _amount);
    }
}