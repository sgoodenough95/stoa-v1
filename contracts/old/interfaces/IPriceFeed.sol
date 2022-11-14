// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface IPriceFeed {

    function getPrice(address _token) external view returns (uint _price);
}