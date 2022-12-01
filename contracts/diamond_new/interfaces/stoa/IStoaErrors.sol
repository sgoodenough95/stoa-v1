// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title  IStoaErrors
/// @author The Stoa Corporation Ltd.

interface IStoaErrors {

    error IllegalArgument(uint8 argument);

    error TokenDisabled(address token);
}