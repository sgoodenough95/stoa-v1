// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IController.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/ISafeOperations.sol";
import "./interfaces/IPriceFeed.sol";
import "./utils/StableMath.sol";
import { RebaseOpt } from "./utils/RebaseOpt.sol";
import { Common } from "./utils/Common.sol";

/**
 * @dev
 *  Stores Safe data.
 *  Each Safe supports one type of collateral asset.
 *  Stores liquidation logic. Keepers can liquidate Safes where their CR is breached.
 *  TBD whether we have a separate 'ActivePool' contract (for each active-debt Token pair)
 *  that holds collateral and tracks debts.
 * @notice
 *  Contract that owns Safes. Holds 'activated' (yield-bearing) Stoa tokens, owned by Safe owners.
 *  Does not hold 'unactivated' tokens as they have no functionality as a Safe asset, but
 *  are purely debt tokens (similar to Dai's Vaults).
 */
contract SafeManager is RebaseOpt, Common, ReentrancyGuard {
    using StableMath for uint256;

    address public priceFeed;   // N

    IPriceFeed priceFeedContract;   // N

    /**
     * @dev
     *  Counter that increments each time an address opens a Safe.
     *  Enables us to identify one of the user's Safes.
     *  E.g., Safe 1: BTCSTa => USDST, Safe 2: BTCSTa => EURST.
     *  Reason being, for now, only allow one debtToken per Safe.
     */
    mapping(address => uint) currentSafeIndex;  // X

    /**
     * @dev Safe owner => safeIndex => Safe.
     */
    mapping(address => mapping(uint => Safe)) public safe;  // X

    /**
     * @dev Referred to by other contracts.
     */
    mapping(address => address) public tokenToAP;   // X

    /**
     * @dev activeToken-debtToken => Max Collateralization Ratio.
     *  MCR measured in basis points.
     *  For active-unactive counterparts, will always be 200% (MCR = 20_000).
     *  E.g., to mint 1,000 USDST, you would require 2,000 USDSTa.
     * @notice
     *  Can only borrow unactive (non-yield-bearing) Stoa tokens (e.g., USDST).
     *  If returns 0, then the debtToken is not supported for the activeToken,
     *  and vice versa.
     */
    mapping(address => mapping(address => uint)) public activeToDebtTokenMCR;   // X

    mapping(address => address) public activeToUnactiveCounterpart; // X

    /**
     * @dev Start with one available debtToken per activeToken to begin with.
     */
    mapping(address => address[]) public activeTokenToSupportedDebtTokens;  // X

    /**
     * @notice
     *  Minimum amount of debtToken that can be minted upon a borrow request.
     *  E.g., Min amount of 100 USDST can be minted upon borrow.
     */
    mapping(address => uint) debtTokenMinMint;  // X

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation
    }   // X

    /**
     * @notice
     *  For now, one Safe supports one type of activeToken and one type of debtToken.
     * @dev
     *  Do not need to include a parameter to indiciate if a Safe is underwater.
     *  This is because, as a Safe supports one type of activeToken and debtToken,
     *  there will be some ratio where, if equal to or greater than, the Safe will be
     *  deemed underwater and can be liquidated.
     *  This ratio will vary between activeToken-debtToken pairs.
     */
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
        Status status;
    }   // X

    constructor(address _priceFeed) {
        priceFeed = _priceFeed;
    }

    /**
     * @notice Function to verify Safe's activeToken.
     */
    function getSafeInit(
        address _owner,
        uint _index
    )
        external
        view
        returns (address, address, address) {
        return (
            safe[_owner][_index].owner,
            safe[_owner][_index].activeToken,
            safe[_owner][_index].debtToken
        );
    }

    function getSafeVal(
        address _owner,
        uint _index
    )
        external
        view
        returns (uint, uint, uint, uint)
    {
        return (
            safe[_owner][_index].bal,
            safe[_owner][_index].mintFeeApplied,
            safe[_owner][_index].redemptionFeeApplied,
            safe[_owner][_index].debt
        );
    }

    function getSafeStatus(
        address _owner,
        uint _index
    )  
        external
        view
        returns (uint)
    {
        return uint(safe[_owner][_index].status);
    }


    function initializeSafe(
        address _owner,
        address _activeToken,
        uint _amount,
        uint _mintFeeApplied,
        uint _redemptionFeeApplied
    )
        external
        onlySafeOps
    {
        // First, find the user's current index.
        uint _index = currentSafeIndex[_owner];

        // Now set Safe params.
        safe[_owner][_index].owner = _owner;
        safe[_owner][_index].activeToken = _activeToken;
        safe[_owner][_index].bal = _amount;
        safe[_owner][_index].mintFeeApplied = _mintFeeApplied;
        safe[_owner][_index].redemptionFeeApplied = _redemptionFeeApplied;
        safe[_owner][_index].index = _index;
        safe[_owner][_index].status = Status(1);

        // Increment index (this will be used for the next Safe the user opens).
        currentSafeIndex[_owner] += 1;
    }

    /**
     * @dev Safe balance setter, called only by SafeOperations
     * @param _owner The owner of the Safe.
     * @param _index The Safe's index.
     * @param _amount The amount of apTokens.
     * @param _add Boolean to indicate if adding or subtracting.
     */
    function adjustSafeBal(
        address _owner,
        uint _index,
        uint _amount,
        // uint _mintFeeApplied,
        // uint _redemptionFeeApplied,
        bool _add
    )
        external
        onlySafeOps
    {
        require(safe[_owner][_index].status == Status(1), "SafeManager: Safe not active");
        
        if (_add == true) {
            safe[_owner][_index].bal += _amount;
        } else {
            require(safe[_owner][_index].bal >= _amount, "SafeManager: Safe cannot have negative balance");
            safe[_owner][_index].bal -= _amount;
        }
    }

    /**
     * @dev Safe debt setter, called only by SafeOperations.
     * @param _owner The owner of the Safe.
     * @param _index The Safe's index.
     * @param _debtToken The Safe's debtToken.
     * @param _amount The amount of debtTokens.
     * @param _fee The amount of apTokens captured as an originationFee.
     * @param _add Boolean to indicate if increasing debt.
     */
    function adjustSafeDebt(
        address _owner,
        uint _index,
        address _debtToken,
        uint _amount,    // debtTokens
        uint _fee,  // apTokens
        bool _add
    )
        external
        onlySafeOps
    {
        require(safe[_owner][_index].debtToken == _debtToken, "SafeManager: debtToken mismatch");
        require(safe[_owner][_index].status == Status(1), "SafeManager: Safe not active");

        // Repaying debt
        if (_add == false) {
            require(
                _amount <= safe[_owner][_index].debt, "SafeManager: Safe cannot have negative debt"
            );
            safe[_owner][_index].debt -= _amount;
        }
        // Increasing debt
        else {
            safe[_owner][_index].debt += _amount;
            safe[_owner][_index].originationFeesPaid += _fee;
        }
    }

    /**
     * @dev Safe Status setter, called only by SafeOperations.
     * @param _owner The owner of the Safe.
     * @param _index The Safe's index.
     * @param _activeToken The Safe's activeToken.
     * @param _num Parameter for selecting the Status.
     */
    function setSafeStatus(
        address _owner,
        uint _index,
        address _activeToken,
        uint _num
    )
        external
        onlySafeOps
    {
        // Additional check, may later be removed.
        require(
            safe[_owner][_index].activeToken == _activeToken,
            "SafeManager: activeToken mismatch"
        );
        safe[_owner][_index].status = Status(_num);
    }

    function initializeBorrow(
        address _owner,
        uint _index,
        address _debtToken
    )
        external
        onlySafeOps
    {
        safe[_owner][_index].debtToken = _debtToken;
    }

    /**
     * @notice
     *  View function that returns true if a Vault can be liquidated.
     */
    function isUnderwater(address _owner, uint _index)
        external
        view
        returns (bool, uint CR)
    {
        address activeToken = safe[_owner][_index].activeToken;
        address debtToken = safe[_owner][_index].debtToken;

        // require(
        //     activeToUnactiveCounterpart[activeToken] != debtToken,
        //     "SafeManager: Cannot liquidate counterparts"
        // );
        // require(
        //     activeToDebtTokenMCR[activeToken][debtToken] != 0,
        //     "SafeManager: Invalid pair"
        // );

        IERC4626 activePool = IERC4626(this.getActivePool(activeToken));
        uint assets = activePool.previewRedeem(safe[_owner][_index].bal);
        console.log("Safe assets: %s", assets);
        uint debt = safe[_owner][_index].debt;

        uint activeTokenPrice = priceFeedContract.getPrice(activeToken);
        console.log("activeToken price: %s", activeTokenPrice);
        uint debtTokenPrice = priceFeedContract.getPrice(debtToken);
        console.log("debtToken price: %s", debtTokenPrice);

        uint MCR = activeToDebtTokenMCR[activeToken][debtToken];
        console.log("Minimum Collateralisation Ratio: %s", MCR);
        CR = (assets * activeTokenPrice)
            .divPrecisely(debt * debtTokenPrice).mulTruncate(10_000);
        console.log("Safe Collateralisation Ratio: %s", CR);

        if (CR > MCR) return (false, CR);
        else return (true, CR);
    }

    function getMaxBorrow(address _owner, uint _index, address _debtToken)
        public
        view
        returns (uint maxBorrow)
    {
        address activeToken = safe[_owner][_index].activeToken;
        address debtToken = safe[_owner][_index].debtToken;

        IERC4626 activePool = IERC4626(this.getActivePool(activeToken));
        uint assets = activePool.previewRedeem(safe[_owner][_index].bal);

        uint activeTokenPrice = priceFeedContract.getPrice(activeToken);

        if (debtToken == address(0)) {
            debtToken = _debtToken;
        }

        uint MCR = getActiveToDebtTokenMCR(activeToken, debtToken);

        maxBorrow = ((assets * 10_000) / MCR) * activeTokenPrice / 10**18;
    }

    function setActiveToDebtTokenMCR(address _activeToken, address _debtToken, uint _MCR)
        external
    {
        activeToDebtTokenMCR[_activeToken][_debtToken] = _MCR;
    }

    function getActiveToDebtTokenMCR(address _activeToken, address _debtToken)
        public
        view
        returns (uint _MCR)
    {
        return activeToDebtTokenMCR[_activeToken][_debtToken];
    }

    function setUnactiveCounterpart(address _activeToken, address _unactiveToken)
        external
    {
        activeToUnactiveCounterpart[_activeToken] = _unactiveToken;
    }

    function getUnactiveCounterpart(address _activeToken)
        public
        view
        returns (address unactiveToken)
    {
        return activeToUnactiveCounterpart[_activeToken];
    }

    function setActivePool(address _token, address _activePool)
        external
    {
        tokenToAP[_token] = _activePool;
    }

    function setPriceFeed(address _priceFeed)
        external
    {
        priceFeed = _priceFeed;
        priceFeedContract = IPriceFeed(priceFeed);
    }

    function getActivePool(address _token)
        external
        view
        returns (address activePool)
    {
        activePool = tokenToAP[_token];
    }

    // function liquidateSafe(address _owner, uint _index)
    //     external
    //     nonReentrant
    // {
    //     require(
    //         this.isUnderwater(_owner, _index),
    //         "SafeManager: Safe not underwater"
    //     );
    //     // liquidation logic.
    // }
}