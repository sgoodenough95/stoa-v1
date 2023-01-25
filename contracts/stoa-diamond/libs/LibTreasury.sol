// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {
    AppStorage,
    LibAppStorage
} from "./LibAppStorage.sol";

library LibTreasury {

    function _adjustBackingReserve(
        address wildToken,      // unactiveToken (e.g., USDST).
        address backingToken,   // activeToken (e.g., USDSTA).
        int256  amount
    ) internal returns (int newBackingReserve) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        s.backingReserve[wildToken][backingToken] += amount;

        return s.backingReserve[wildToken][backingToken];
    }
}