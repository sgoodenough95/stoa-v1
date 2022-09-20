// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {

    uint256 tokenBaseUnits = 10 ** 18;

    constructor() ERC20 ("Test Token", "TKN") {
      _mint(msg.sender, 10_000 * tokenBaseUnits);
    }

    function mint(
        address to,
        uint amount
    ) external returns (bool) {
      _mint(to, amount);
      return true;
    }
}