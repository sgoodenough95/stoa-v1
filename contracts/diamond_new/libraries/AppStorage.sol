// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "../interfaces/IERC4626.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IActivated.sol";
import "../interfaces/IUnactivated.sol";
import "../interfaces/ISafeManager.sol";

struct AppStorage {
    //Activator Facet
    // @dev the synthetic token to be exchanged
    address syntheticToken;
    // @dev the underlyinToken token to be received
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
    // PriceFeedFacet
    mapping(address => uint) tokenPrice;
    // SafeOperationsFacet

    /**
     * @dev Universal + Token state variables 
     */
    bool isPaused;
    mapping(address => address) activeToUnactiveCounterpart;
    mapping(address => address[]) activeTokenToSupportedDebtTokens;
    mapping(address => address[]) tokenToAPs;
    mapping(address => address[]) activeToInputTokens;

    /**
     * Safe state variables
     */
    mapping(address => uint) currentSafeIndex;
    mapping(address => mapping(uint => Safe)) safe;
    mapping(address => address) tokenToAP; // Universal (?)
    mapping(address => mapping(address => uint)) activeToDebtTokenMCR;
    mapping(address => uint) debtTokenMinMint;
    mapping(address => uint) minBorrow;

    /**
     * @dev Activator state variables
     */
    mapping(address => ActivatorAccount) accounts;

    /**
     * @dev Controller state variables
     */
    // mapping(address => address) tokenToController;   // No longer needed
    mapping(address => address) tokenToVenue;
    mapping(address => uint) unactiveRedemptionAllowance;
    /**
     * @notice Stat collection.
     */
    mapping(address => uint) amountDeposited;
    mapping(address => uint) amountWithdrawn;
    mapping(address => address[]) tokenToYieldVenues;
    mapping(address => mapping(address => uint)) accruedYield;
    // mapping(address => uint) totalYieldAccrued;  
    mapping(address => uint) holderTotalYieldAccrued;
    mapping(address => mapping(address => uint)) holderTokenYieldAccrued;
    mapping(address => uint) stoaYieldAccrued;  // Can add for specific token
    mapping(address => uint) originationFeesCollected;
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
    mapping(address => address) activeToInputToken; // + Activator
    mapping(address => uint) originationFeesCollected;

    /**
     * @dev Treasury state variables.
     */
    mapping(address => mapping(address => int)) backingReserve;
    mapping(address => uint) apTokens;
    mapping(address => uint) buffer;
    
    /**
     * @dev Price Feed state variables.
     */
    mapping(address => uint) tokenPrice; // Universal (?)
}

struct Safe {
    address owner;
    // // E.g., USDST
    address activeToken;
    // E.g., USDSTu
    // Might not necessarily know this when opening a Safe.
    address debtToken;
    // activeToken creditBalance;
    uint bal;   // apTokens / shares
    // Increments only if depositing activeToken.
    uint mintFeeApplied;
    uint redemptionFeeApplied;
    uint originationFeesPaid;   // credits
    // Balance of the debtToken.
    uint debt;  // tokens
    uint index;
    SafeStatus status;
}

enum SafeStatus {
    nonExistent,
    active,
    closedByOwner,
    closedByLiquidation
}
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