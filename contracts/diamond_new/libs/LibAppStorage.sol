// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

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

struct YieldTokenParams {
    // May later need if handling USDT.
    uint8 decimals;
    
    uint8 adapterId;

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
    mapping(address => uint)    unactiveRedemptionAllowance;
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
    mapping(address => uint) mintFee;
    mapping(address => uint) redemptionFee;
    mapping(address => uint) mgmtFee;
    mapping(address => uint) originationFee;

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
        assembly {
            ds.slot := 0
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
}