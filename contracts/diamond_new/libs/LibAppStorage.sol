// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { LibDiamond } from ".././diamond/libs/LibDiamond.sol";

/**
 * @dev Leave for now, may not need for Diamond
 */
struct CacheInit {
    address owner;
    address activeToken;
    address debtToken;
}

struct CacheVal {
    uint bal;
    uint mintFeeApplied;
    uint redemptionFeeApplied;
    uint debt;
}

// e.g., DAI
struct UnderlyingTokenParams {
    // May later need if handling USDT.
    uint8   decimals;
    uint256 conversionFactor;
    uint8   enabled;
}

// e.g., yvDAI
// Change to 'TokenParams' (?)
struct YieldTokenParams {
    // uint8   decimals;
    address underlyingToken;
    address activeToken;
    address unactiveToken;
    address yieldVenue;
    // Limit for the amount of underlying tokens that can be deposited.
    uint256 depositLimit;
    uint8   enabled;
}

// e.g., yvDAIST
struct StoaTokenParams {
    uint8   rebasing;
    address yieldToken;
    uint8   enabled;
}

// e.g., ap-yvDAIST (share tokens, used to track Safe bals)
struct ActivePoolTokenParams {
    address stoaToken;
    uint8   enabled;
}

struct ActivatorAccount {
    // The total number of unexchanged tokens that an account has deposited into the system
    uint256 unexchangedBalance;
    // The total number of exchanged tokens that an account has had credited
    uint256 exchangedBalance;
}

// struct UpgradeActivatorAccount {
//     // The owner address whose account will be modified
//     address user;
//     // The amount to change the account's unexchanged balance by
//     int256 unexchangedBalance;
//     // The amount to change the account's exchanged balance by
//     int256 exchangedBalance;
// }

struct AppStorage {
    /**
     * @dev May need for Activator
     */
    /// @dev the synthetic token to be exchanged
    address syntheticToken;
    /// @dev the underlyinToken token to be received
    address underlyingToken;

    // ControllerFacet
    // address safeManager;
    // /**
    //  * @notice
    //  *  Collects fees, backing tokens (+ yield) and
    //  *  liquidation gains.
    //  *  Allocates as necessary (e.g., depositing USDST backing
    //  *  tokens into the Curve USDST AcivePool).
    //  */
    // address treasury;
    address activeToken;
    address unactiveToken;
    address inputToken;

    /**
     * @dev Universal + Token state variables 
     */
    bool isPaused;
    mapping(address => address)     activeToUnactiveCounterpart;
    mapping(address => address[])   activeTokenToSupportedDebtTokens;
    mapping(address => address[])   tokenToAPs;
    mapping(address => address[])   activeToInputTokens;

    /**
     * Safe state variables
     */
    mapping(address => uint)    currentSafeIndex;
    mapping(address => address) tokenToAP; // Universal (?)
    mapping(address => uint)    debtTokenMinMint;
    mapping(address => uint)    minBorrow;
    // mapping(address => mapping(uint => Safe))       safe;
    mapping(address => mapping(address => uint))    activeToDebtTokenMCR;

    /**
     * @dev Activator state variables
     */
    mapping(address => ActivatorAccount) accounts;

    /**
     * @dev Controller state variables
     */
    // E.g., DAI => DAI Vault.
    mapping(address => address) tokenToVenue;
    mapping(address => mapping(address => uint))unactiveRedemptionAllowance;
    mapping(address => UnderlyingTokenParams)   _underlyingTokens;
    mapping(address => YieldTokenParams)        _yieldTokens;
    mapping(address => StoaTokenParams)         _stoaTokens;
    mapping(address => ActivePoolTokenParams)   _activePoolTokens;

    /**
     * @notice Stat collection.
     */
    mapping(address => uint) amountDeposited;
    mapping(address => uint) amountWithdrawn;
    mapping(address => uint) holderTotalYieldAccrued;
    mapping(address => uint) stoaYieldAccrued;  // Can add for specific token
    mapping(address => uint) originationFeesCollected;
    mapping(address => mapping(address => uint)) accruedYield;
    mapping(address => mapping(address => uint)) holderTokenYieldAccrued;

    /**
     * @notice Fees in basis points (e.g., 30 = 0.3%).
    */
    mapping(address => uint256) mintFee;
    mapping(address => uint256) redemptionFee;
    mapping(address => uint256) mgmtFee;
    mapping(address => uint256) originationFee;

    /**
     * @notice Limits
     */
    mapping(address => uint256) minDeposit;

    /**
     * @dev
     *  Later use for self-repaying loan logic.
     */
    mapping(address => bool) isActiveToken; // + Activator

    /**
     * @dev Treasury state variables.
     */
    mapping(address => uint) apTokens;
    mapping(address => uint) buffer;
    mapping(address => mapping(address => int)) backingReserve;
    
    /**
     * @dev Price Feed state variables.
     */
    mapping(address => uint) tokenPrice; // Universal (?)
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