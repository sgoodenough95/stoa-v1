// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDST is ERC20 {

    constructor(
        // string memory _name,
        // string memory _symbol
    ) ERC20("Stoa Dollar", "USDST") {}

    function sendToPool() external {}

    function returnFromPool() external {}
}