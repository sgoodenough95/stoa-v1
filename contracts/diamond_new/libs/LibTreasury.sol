// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {
    AppStorage,
    YieldTokenParams,
    LibAppStorage
} from "./LibAppStorage.sol";

library LibTreasury {

    function _adjustBackingReserve(
        address wildToken,
        address backingToken,
        int     amount
    ) internal returns (int newBackingReserve) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        newBackingReserve = s.backingReserve[wildToken][backingToken] += amount;
    }
}