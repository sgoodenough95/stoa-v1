// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./stoa/IStoaActions.sol";
import "./stoa/IStoaErrors.sol";
import "./stoa/IStoaEvents.sol";

/// @title  IStoa
/// @author The Stoa Corporation Ltd.

interface IStoa is
    IStoaActions,
    IStoaErrors,
    IStoaEvents
{}