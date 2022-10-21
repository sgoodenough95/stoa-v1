// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./utils/Common.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IController.sol";
import "./interfaces/ISafeManager.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/IUnactivated.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IUnactivated.sol";
import "./interfaces/ITreasury.sol";

/**
 * @dev
 *  Stores Safe data in and makes calls to SafeManager contract.
 *  Stores token-Controller mapping.
 *  Calls mint/burn of unactivated tokens upon borrow/repay.
 *  Moves liquidatable collateral to ActivePool.
 *  Enables depositing into StabilityPool directly from Safe.
 * @notice
 *  Contains user-operated functions for managing Safes.
 */
contract SafeOperations is ReentrancyGuard, Common {

    address public safeManager;

    address public treasury;

    address public priceFeed;

    ISafeManager safeManagerContract;

    ITreasury treasuryContract;

    IPriceFeed priceFeedContract;

    mapping(address => address) public tokenToController;

    /**
     * @dev
     *  Later use for self-repaying loan logic.
     */
    mapping(address => bool) public isActiveToken;

    mapping(address => address) public activeToInputToken;

    /**
     * @notice
     *  One-time fee charged upon debt issuance, measured in basis points.
     *  Leave as fixed for now.
     */
    uint public originationFee = 200 * 10 ** 18;    // tokens

    uint public originationFeeCollected;

    uint public minBorrow = 2_000 * 10 ** 18; // tokens

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

    uint cacheStatus;

    constructor(address _safeManager, address _priceFeed) {
        safeManager = _safeManager;
        priceFeed = _priceFeed;
        safeManagerContract = ISafeManager(safeManager);
        priceFeedContract = IPriceFeed(priceFeed);
    }

    /**
     * @dev
     *  Returns the controller for a given token (inputToken or activeToken).
     *  TBD whether this is handled by a separate Router contract.
     * @return address The address of the target controller.
     */
    function getController(address _token)
        external
        view
        returns (address)
    {
        return tokenToController[_token];
    }

    /**
     * @dev
     *  Transfers tokens from caller to target Controller (unless the token is an activeToken,
     *  in which case transfers directly to SafeManager).
     *  Require a separate function / add-on to allow borrowing also in one tx
     *  (or just call both functions ?)
     * @notice User-facing function for opening a Safe.
     * @param _token The address of the token. Must be supported.
     * @param _amount The amount of tokens to deposit.
     */
    function openSafe(address _token, uint _amount)
        external
        nonReentrant
    {
        // First, check if a Controller exists for the token.
        require(tokenToController[_token] != address(0), "SafeOps: Controller not found");

        address _targetController = tokenToController[_token];

        IController targetController = IController(_targetController);

        // E.g., _token = DAI.
        if (validInputToken(_token)) {
            console.log("Opening Safe with inputToken: %s", _token);

            address activeToken = targetController.getActiveToken();

            // Need to approve Vault spend for token first.
            uint apTokens = targetController.deposit(msg.sender, _amount, true);
            console.log(
                "Deposited %s inputTokens from %s to Controller",
                _amount,
                msg.sender
            );
            console.log(
                "Safe opened with %s apTokens",
                apTokens
            );

            safeManagerContract.initializeSafe({
                _owner: msg.sender,
                _activeToken: activeToken,
                _amount: apTokens,   // Do not apply mintFee
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
            console.log("Initialized Safe instance");
        }
        // E.g., _token = USDSTa.
        else {
            require(validActiveToken(_token));
            console.log("Opening a Safe with activeToken: %s", _token);

            IERC4626 activePool = IERC4626(
                safeManagerContract.getActivePool(_token)
            );

            // Need to approve SafeOperations spend for token first.
            // Deposit to activePool. Controller receives apTokens.
            uint apTokens = activePool.deposit(
                _amount,
                _targetController,
                msg.sender
            );
            console.log(
                "Deposited %s activeTokens from %s to ActivePool",
                _amount,
                msg.sender
            );
            console.log(
                "Safe opened with %s apTokens",
                apTokens
            );

            safeManagerContract.initializeSafe({
                _owner: msg.sender,
                _activeToken: _token,
                _amount: apTokens,
                _mintFeeApplied: _amount,   // Mark mintFee as already paid for.
                _redemptionFeeApplied: 0
            });
            console.log("Initialized Safe instance");
        }
        // Later add option for unactiveTokens.
    }

    /**
     * @notice
     *  Safe owners can deposit either activeTokens or inputTokens (e.g., USDSTa or DAI).
     *  Can only deposit if the Safe supports that token.
     * @param _token The token to deposit (e.g., DAI, USDSTa, etc.).
     * @param _index Identifier for the Safe.
     * @param _amount The amount to deposit.
     */
    function depositToSafe(address _token, uint _index, uint _amount)
        external
        nonReentrant
    {
        // First, check if a Controller exists for the token.
        require(tokenToController[_token] != address(0), "SafeOps: Controller not found");

        address _targetController = tokenToController[_token];

        IController targetController = IController(_targetController);

        // E.g., _token = DAI.
        if (validInputToken(_token)) {

            address activeToken = targetController.getActiveToken();

            uint apTokens = targetController.deposit(msg.sender, _amount, true);
            console.log(
                "Deposited %s inputTokens from %s to Controller",
                _amount,
                msg.sender
            );

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _activeToken: activeToken,
                _amount: apTokens,
                _add: true,
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
        }
        // E.g., _token = USDSTa.
        else {
            require(validActiveToken(_token));
            console.log("Depositing to Safe with activeToken: %s", _token);

            IERC4626 activePool = IERC4626(
                safeManagerContract.getActivePool(_token)
            );

            // Need to approve SafeOperations spend for token first.
            // Deposit to activePool. Controller receives apTokens.
            uint apTokens = activePool.deposit(_amount, _targetController);
            console.log(
                "Deposited %s activeTokens from %s to ActivePool",
                _amount,
                msg.sender
            );
            console.log(
                "Deposited %s apTokens to Safe",
                apTokens
            );

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _activeToken: _token,
                _amount: apTokens,
                _add: true,
                _mintFeeApplied: _amount,
                _redemptionFeeApplied: 0
            });
        }
        // For now at least, do not allow unactiveToken deposits.
    }

    /**
     * @notice
     *  Safe owners can withdraw either activeTokens or inputTokens (e.g., USDSTa or DAI).
     * @param _activated Boolean to indicate withdrawal of activeToken (true) or inputToken (false).
     * @param _index Identifier for the Safe.
     * @param _amount The amount to withdraw (in apTokens).
     */
    function withdrawTokens(bool _activated, uint _index, uint _amount)
        external
        nonReentrant
        // returns (uint tokenAmount, int feeCoverage, uint mintFeeChange, uint redemptionFeeChange)
    {
        CacheInit memory cacheInit;

        (
            cacheInit.owner,
            cacheInit.activeToken,
            cacheInit.debtToken
        ) = safeManagerContract.getSafeInit(msg.sender, _index);

        CacheVal memory cacheVal;

        (
            cacheVal.bal,  // apTokens
            cacheVal.mintFeeApplied,
            cacheVal.redemptionFeeApplied,
            cacheVal.debt
        ) = safeManagerContract.getSafeVal(msg.sender, _index);

        require(msg.sender == cacheInit.owner, "SafeOps: Owner mismatch");
        require(_amount <= cacheVal.bal, "SafeOps: Insufficient balance");

        // Locate the activeToken's Controller.
        address _targetController = tokenToController[cacheInit.activeToken];

        IController targetController = IController(_targetController);     

        // Transfer requested tokens to withdrawer.
        targetController.withdrawTokensFromSafe(
            msg.sender,
            _activated,
            _amount
            // feeCoverage
        );

        // Update Safe params.
        safeManagerContract.adjustSafeBal({
            _owner: msg.sender,
            _index: _index,
            _activeToken: cacheInit.activeToken,
            _amount: _amount,   // apTokens
            _add: false,
            _mintFeeApplied: 0, // mintFeeChange
            _redemptionFeeApplied: 0    // redemptionFeeChange
        });

        // If Safe is empty then mark it as closed.
        if (_amount == cacheVal.bal) {
            safeManagerContract.setSafeStatus(msg.sender, _index, cacheInit.activeToken, 2);
            console.log("Safe closed by owner");
        }
    }

    /**
     * @notice
     *  Function to initialize a borrow from a Safe. Once a debtToken has been initialized,
     *  the owner cannot borrow another type of debtToken from the Safe (e.g., if borrowing
     *  USDST, cannot then borrow GBPST from the same Safe).
     * @param _index The Safe to initialize a borrow against.
     * @param _debtToken The debtToken to be initialized.
     * @param _amount The amount of debtTokens to borrow (limited by the Safe bal and CR).
     * @param _initialize Indicated whether a borrow is being initialized.
     */
    function borrow(uint _index, address _debtToken, uint _amount, bool _initialize)
        external
    {
        require(_amount >= minBorrow, "SafeOps: Borrow amount too low");

        // First, get the Safe params.
        CacheInit memory cacheInit;

        (
            cacheInit.owner,
            cacheInit.activeToken,
            cacheInit.debtToken
        ) = safeManagerContract.getSafeInit(msg.sender, _index);

        CacheVal memory cacheVal;

        (
            cacheVal.bal,   // apTokens
            cacheVal.mintFeeApplied,
            cacheVal.redemptionFeeApplied,
            cacheVal.debt, // unactiveTokens
            cacheVal.locked // apTokens
        ) = safeManagerContract.getSafeVal(msg.sender, _index);

        require(msg.sender == cacheInit.owner, "SafeOps: Owner mismatch");

        if (_initialize == true) {
            require(
                cacheInit.debtToken == address(0),
                "SafeOps: debtToken already initialized - please pay off debt first"
            );
        } else {
            require(
                cacheInit.debtToken != address(0),
                "SafeOps: debtToken not initialized"
            );
        }

        // Find the Safe's maxBorrow.
        (address activePool, uint maxBorrow, uint MCR, uint oFeeShares) = computeBorrowAllowance(
            cacheInit.activeToken,
            cacheVal.bal,
            _debtToken
        );
        console.log("Max borrow: %s", maxBorrow);
        require(_amount <= maxBorrow, "SafeOps: Insufficient funds for borrow amount");

        uint CR = computeCR(cacheInit.activeToken, _debtToken, _amount, cacheVal.bal);
        console.log("CR: %s", CR);
        require(
            CR > MCR,
            "SafeOps: Insuffiicient collateral posted to meet MCR"
        );

        // Find originationFee worth of apTokens + make available to Treausry.
        // Treasury holds apTokens / has a dedicated Safe (?)
        treasuryContract.adjustAPTokenBal(activePool, oFeeShares);

        // Update Safe params - ensure correct.
        if (_initialize == true) {
            safeManagerContract.initializeBorrow({
                _owner: cacheInit.owner,
                _index: _index,
                _debtToken: _debtToken
            });
            console.log("Initialized borrow");
        }

        // Later add mapping (?)
        originationFeeCollected += originationFee;

        safeManagerContract.adjustSafeDebt({
            _owner: cacheInit.owner,
            _index: _index,
            _debtToken: _debtToken,
            _amount: _amount
        });
        console.log("Adjusted Safe debt");

        IUnactivated unactiveToken = IUnactivated(_debtToken);

        unactiveToken.mint(msg.sender, _amount);
        console.log("Minted %s unactiveTokens to %s", _amount, msg.sender);
    }

    function repay(uint _amount)
        external
        nonReentrant
    {

    }

    function transferActiveTokens(
        address _activeToken,
        uint _index,
        uint _amount,
        address _to,
        uint _toIndex
    )
        external
        nonReentrant
    {

    }

    function transferDebtTokens(
        address _debtToken,
        uint _index,
        uint _amount,
        uint _newIndex
    )
        external
        nonReentrant
    {

    }

    /**
     * @param _activeToken The collateral to borrow against.
     * @param _bal The amount of activeToken collateral (in tokens, not credits).
     * @param _debtToken The debtToken to be minted.
     */
    function computeBorrowAllowance(address _activeToken, uint _bal, address _debtToken)
        public
        view
        returns (address _activePool, uint maxBorrow, uint MCR, uint oFeeShares)
    {
        // First, find the ActivePool contract of the activeToken.
        _activePool = safeManagerContract.getActivePool(_activeToken);

        IERC4626 activePool = IERC4626(_activePool);

        // Second, get the pricePerShare for the _bal
        uint assets = activePool.previewRedeem(_bal);

        // First need to find originationFee worth of apTokens.
        uint activeTokenPrice = priceFeedContract.getPrice(_activeToken);
        console.log("activeToken price: %s", activeTokenPrice);
        uint oFeeTokens = activeTokenPrice / originationFee;
        console.log("originationFee worth of activeTokens: %s", oFeeTokens);
        oFeeShares = activePool.previewMint(oFeeTokens);
        console.log("originationFee worth of apTokens: %s", oFeeShares);

        // E.g., 20,000bp.
        MCR = safeManagerContract.getActiveToDebtTokenMCR(_activeToken, _debtToken);

        // Later change to divPrecisely (?)
        maxBorrow = ((assets - originationFee) * 10_000) / MCR;
    }

    function computeCR(address _activeToken, address _debtToken, uint _amount, uint _debtAmount)
        public
        view
        returns (uint CR)
    {
        if (safeManagerContract.getUnactiveCounterpart(_activeToken) == _debtToken) {
            CR = 20_000;
        } else {
            uint activeTokenPrice = priceFeedContract.getPrice(_activeToken);
            uint debtTokenPrice = priceFeedContract.getPrice(_debtToken);
            CR = ((_amount * activeTokenPrice) - originationFee) / (_debtAmount * debtTokenPrice) * 10_000;
        }
    }

    /**
     * @dev
     *  Want a single source of truth, hence validate with Controller.
     */
    function validActiveToken(address _activeToken)
        internal
        view
        returns (bool)
    {
        IController targetController = IController(tokenToController[_activeToken]);

        if (_activeToken == targetController.getActiveToken()) return true;
        else return false;
    }

    /**
     * @dev
     *  For now, have 2 separate functions for validating input and active tokens.
     */
    function validInputToken(address _inputToken)
        internal
        view
        returns (bool)
    {
        IController targetController = IController(tokenToController[_inputToken]);

        if (_inputToken == targetController.getInputToken()) return true;
        else return false;
    }

    function computeFee(bool _activated, uint _mintFeeApplied, uint _redemptionFeeApplied, uint _amount)
        internal
        pure
        returns (int feeCoverage, uint mintFeeChange, uint redemptionFeeChange)
    {
        uint feeApplied = _activated == true
            ? _mintFeeApplied
            : _redemptionFeeApplied;

        // If > 0, means that the user is "minting" or redeeming |feeCoverage| amount of tokens,
        // for which they are required to pay fees. Both _amount and feeApplied are in tokens.
        feeCoverage = int(_amount - feeApplied);

        uint feeChange = feeCoverage > 0 ? feeApplied : _amount;
        (mintFeeChange, redemptionFeeChange) = (feeChange, feeChange);
        
        // _activated == true
        //     ? (feeChange, uint(0))
        //     : (0, feeChange);
    }

    /**
     * @dev Admin function to set the Controller of a given inputToken.
     */
    function setController(address _token, address _controller)
        external
    {
        tokenToController[_token] = _controller;
    }

    function setTreasury(address _treasury)
        external
    {
        treasury = _treasury;
    }
}