// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { LibDiamond } from ".././diamond-core/libs/LibDiamond.sol";

/// @notice Unused.
// struct CacheInit {
//     address owner;
//     address activeToken;
//     address debtToken;
// }
// struct CacheVal {
//     uint bal;
//     uint mintFeeApplied;
//     uint redemptionFeeApplied;
//     uint debt;
// }
// struct UnderlyingTokenParams {
//     // May later need if handling USDT.
//     uint8   decimals;
//     uint256 conversionFactor;
//     uint8   enabled;
// }
// struct VaultTokenParams {
//     uint8 enabled;
// }
// struct StoaTokenParams {
//     uint8   rebasing;
//     // address yieldToken;
//     uint8   enabled;
// }
// struct ActivePoolTokenParams {
//     address stoaToken;
//     uint8   enabled;
// }
// struct ActivatorAccount {
//     // The total number of unexchanged tokens that an account has deposited into the system
//     uint256 unexchangedBalance;
//     // The total number of exchanged tokens that an account has had credited
//     uint256 exchangedBalance;
// }
// struct UpgradeActivatorAccount {
//     // The owner address whose account will be modified
//     address user;
//     // The amount to change the account's unexchanged balance by
//     int256 unexchangedBalance;
//     // The amount to change the account's exchanged balance by
//     int256 exchangedBalance;
// }

// activeToken maps to an underlyingToken (e.g., DAI) and a vaultToken (e.g., yvDAI).
// underlyingToken and vaultToken can be modified (e.g., via PCV).
struct RefTokenParams {
    // uint8   decimals;
    address underlyingToken;    // modifiable
    address vaultToken;         // modifiable
    address unactiveToken;      // constant
    // Limit for the amount of underlying tokens that can be deposited.
    uint256 depositLimit;
    uint8   enabled;
}

struct AppStorage {

    // msg.sender -> activeToken -> claimableAmount.
    mapping(address => mapping(address => uint256)) _unactiveRedemptions;
    mapping(address => uint256)                     claimableUnactiveBackingReserves;
    mapping(address => mapping(address => int))     backingReserve;
    
    // 'activeToken' is used as the key to fetch reference token parameters.
    mapping(address => RefTokenParams)              _refTokens; // (I)

    mapping(address => uint) holderYieldAccrued;
    mapping(address => uint) stoaYieldAccrued;  // Can add for specific token
    
    /// @notice Fees in basis points (e.g., 30 = 0.3%).
    mapping(address => uint256) mintFee;        // (I)
    mapping(address => uint256) redemptionFee;  // (I)
    mapping(address => uint256) conversionFee;  // (I)
    mapping(address => uint256) originationFee; // (I)
    mapping(address => uint256) mgmtFee;        // (I)

    /// @notice Limits.
    mapping(address => uint256) minDeposit;     // (I)
    mapping(address => uint256) minWithdraw;    // (I)

    /// @notice Unused.
    ///
    /// @dev    Universal + token state vars.
    // uint8 systemPaused;
    // mapping(address => address)     activeToUnactiveCounterpart;
    // mapping(address => address[])   activeTokenToSupportedDebtTokens;
    // mapping(address => address[])   tokenToAPs;
    // mapping(address => address[])   activeToInputTokens;

    /// @dev    Safe state vars.
    // mapping(address => uint)    currentSafeIndex;
    // mapping(address => address) tokenToAP; // Universal (?)
    // mapping(address => uint)    debtTokenMinMint;
    // mapping(address => uint)    minBorrow;
    // mapping(address => mapping(uint => Safe))       safe;
    // mapping(address => mapping(address => uint))    activeToDebtTokenMCR;

    /// @dev    Activator state vars.
    // mapping(address => ActivatorAccount) accounts;

    // mapping(address => UnderlyingTokenParams)   _underlyingTokens;
    // mapping(address => VaultTokenParams)        _vaultTokens;
    // mapping(address => StoaTokenParams)         _stoaTokens;
    // mapping(address => ActivePoolTokenParams)   _activePoolTokens;

    /**
     * @notice Stat collection.
     */
    // mapping(address => uint) amountDeposited;
    // mapping(address => uint) amountWithdrawn;

    // mapping(address => uint) originationFeesCollected;
    // mapping(address => mapping(address => uint)) accruedYield;
    // mapping(address => mapping(address => uint)) holderTokenYieldAccrued;

    /**
     * @dev
     *  Later use for self-repaying loan logic.
     */
    // mapping(address => bool) isActiveToken; // + Activator

    // /**
    //  * @dev Treasury state variables.
    //  */
    // mapping(address => uint) apTokens;
    // mapping(address => uint) buffer;
    // mapping(address => mapping(address => int)) backingReserve;
    
    // /**
    //  * @dev Price Feed state variables.
    //  */
    // mapping(address => uint) tokenPrice; // Universal (?)
}

library LibAppStorage {
    function diamondStorage() internal pure returns (AppStorage storage ds) {
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
}