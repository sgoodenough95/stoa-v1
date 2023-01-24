// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {
    AppStorage,
    RefTokenParams,
    LibAppStorage
} from "./LibAppStorage.sol";
import { LibTreasury } from "./LibTreasury.sol";
import { IERC4626 } from ".././interfaces/IERC4626.sol";
import ".././interfaces/IStoa.sol";
import ".././interfaces/IStoaToken.sol";

/// @title  LibSafe
/// @author The Stoa Corporation Ltd.
/// @notice Internal functions for managing Safes.
library LibSafe {

    /// @notice Initializes a Safe instance.
    ///
    /// @dev    Mint/redemption fees to come later.
    function _initializeSafe(
        address owner,
        address activeToken,
        uint256 amount
    ) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 index = s.currentSafeIndex[owner];

        s.safe[owner][index].owner          = owner;
        s.safe[owner][index].activeToken    = activeToken;
        s.safe[owner][index].bal            = amount;
        s.safe[owner][index].index          = index;
        s.safe[owner][index].status         = 1;

        s.currentSafeIndex[owner] += 1;
    }
}