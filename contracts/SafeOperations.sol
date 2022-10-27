// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

// import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
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
import "./utils/StableMath.sol";

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
    // using SafeMath for uint256;
    using StableMath for uint256;

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

    mapping(address => uint) public originationFeesCollected;

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

    constructor(
        address _safeManager,
        address _priceFeed,
        address _treasury
    ) {
        safeManager = _safeManager;
        priceFeed = _priceFeed;
        treasury = _treasury;
        safeManagerContract = ISafeManager(safeManager);
        priceFeedContract = IPriceFeed(priceFeed);
        treasuryContract = ITreasury(treasury);
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
        console.log("Target controller: %s", _targetController);

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

            uint apTokens = targetController.deposit(msg.sender, _amount, true);
            console.log(
                "Deposited %s inputTokens from %s to Controller",
                _amount,
                msg.sender
            );

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _amount: apTokens,
                _add: true
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
                _amount: apTokens,
                _add: true
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
        (uint apTokenMax, ) = computeWithdrawAllowance(msg.sender, _index);
        require(
            apTokenMax >= _amount, "SafeOps: Insufficient withdrawal allowance"
        );

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
            _amount: _amount,   // apTokens
            _add: false
        });

        // If Safe is empty then mark it as closed.
        if (_amount == cacheVal.bal) {
            safeManagerContract.setSafeStatus(msg.sender, _index, cacheInit.activeToken, 2);
            console.log("Safe closed by owner");
        }
    }

    /**
     * @notice
     *  Once a debtToken has been initialized, the owner cannot borrow another type of 
     *  debtToken from the Safe until it has been paid off.
     * @param _index The Safe to borrow against.
     * @param _debtToken The debtToken to be issued.
     * @param _amount The amount of debtTokens to borrow (limited by the Safe bal and CR).
     * @param _initialize Indicates whether a debtToken is being initialized.
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
            cacheVal.debt // unactiveTokens
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
        // Throws a weird error if require condition not satisfied, need to revisit (?)
        // Need to make work for cross-asset borrows
        require(_amount <= maxBorrow, "SafeOps: Insufficient funds for borrow amount");

        uint CR = computeCR(cacheInit.activeToken, _debtToken, cacheVal.bal, _amount);
        console.log("CR: %s MCR: %s", CR, MCR);
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

        originationFeesCollected[cacheInit.activeToken] += originationFee;

        safeManagerContract.adjustSafeBal({
            _owner: cacheInit.owner,
            _index: _index,
            // Take originationFee from bal.
            _amount: oFeeShares,
            _add: false
        });

        safeManagerContract.adjustSafeDebt({
            _owner: cacheInit.owner,
            _index: _index,
            _debtToken: _debtToken,
            _amount: _amount,
            _fee: oFeeShares,
            _add: true
        });
        console.log("Adjusted Safe debt");

        IUnactivated unactiveToken = IUnactivated(_debtToken);
        unactiveToken.mint(msg.sender, _amount);
        console.log("Minted %s unactiveTokens to %s", _amount, msg.sender);
    }

    /**
     * @param _index The index of the Safe to repay.
     * @param _amount The amount of debtTokens to burn/repay.
     */
    function repay(uint _index, uint _amount)
        external
        nonReentrant
    {
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
            cacheVal.debt // unactiveTokens
        ) = safeManagerContract.getSafeVal(msg.sender, _index);

        require(msg.sender == cacheInit.owner, "SafeOps: Owner mismatch");
        require(_amount <= cacheVal.debt, "SafeOps: invalid repayment amount");

        IUnactivated unactiveToken = IUnactivated(cacheInit.debtToken);
        unactiveToken.burn(msg.sender, _amount);
        console.log("Burned %s tokens from %s", _amount, msg.sender);

        safeManagerContract.adjustSafeDebt({
            _owner: cacheInit.owner,
            _index: _index,
            _debtToken: cacheInit.debtToken,
            _amount: _amount,
            _fee: 0,
            _add: false
        });
        console.log("Adjusted Safe debt");

        // Reset Safe's debtToken if paid off debt.
        if (_amount == cacheVal.debt) {
            safeManagerContract.initializeBorrow(msg.sender, _index, address(0));
        }
    }

    /**
     * @notice Enables activeToken transfers between Safes.
     * @dev
     *  Use apTokens for _amount as more efficient and precise.
     *  Therefore need to perform apToken-activeToken conversion beforehand.
     * @param _index The index of the Safe to transfer activeTokens from.
     * @param _amount The amount of apTokens to transfer.
     * @param _to The address of the Safe owner to transfer activeTokens to.
     * @param _toIndex ID for the receiver's Safe (must support activeToken).
     */
    function transferActiveTokens(
        uint _index,
        uint _amount,   // apTokens
        address _to,
        uint _toIndex
    )
        external
        nonReentrant
    {
        // First, get the sender's Safe params.
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
            cacheVal.debt // unactiveTokens
        ) = safeManagerContract.getSafeVal(msg.sender, _index);

        require(msg.sender == cacheInit.owner, "SafeOps: Owner mismatch");

        (uint apTokenMax, ) = computeWithdrawAllowance(msg.sender, _index);
        require(_amount <= apTokenMax, "SafeOps: Insufficient allownace");

        // Second, get the receiver's Safe params.
        require(
            safeManagerContract.getSafeStatus(_to, _toIndex) == 1,
            "SafeOps: Safe not active"
        );

        CacheInit memory cacheInitTo;

        (
            cacheInitTo.owner,
            cacheInitTo.activeToken,
            cacheInitTo.debtToken
        ) = safeManagerContract.getSafeInit(_to, _toIndex);

        require(
            cacheInit.activeToken == cacheInitTo.activeToken,
            "SafeOps: Safe does not support activeToken"
        );

        safeManagerContract.adjustSafeBal({
            _owner: cacheInit.owner,
            _index: _index,
            _amount: _amount,
            _add: false
        });

        safeManagerContract.adjustSafeBal({
            _owner: cacheInitTo.owner,
            _index: _toIndex,
            _amount: _amount,
            _add: true
        });
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
        // assets [activeTokens]
        uint assets = activePool.previewRedeem(_bal);

        // First need to find originationFee worth of apTokens.
        // (E.g., 1 ETHSTa = $1k)
        uint activeTokenPrice = priceFeedContract.getPrice(_activeToken);
        console.log("activeToken price: %s", activeTokenPrice);

        // (E.g., 1 ETHSTa = $1k: oFeeTokens = $200 / $1k = 0.2 ETHSTa)
        // oFeeTokens [activeTokens]
        uint oFeeTokens = originationFee.divPrecisely(activeTokenPrice);
        console.log("originationFee worth of activeTokens: %s", oFeeTokens);

        // oFeeShares [apTokens]
        oFeeShares = activePool.previewMint(oFeeTokens);
        console.log("originationFee worth of apTokens: %s", oFeeShares);

        // E.g., 20,000bp.
        MCR = safeManagerContract.getActiveToDebtTokenMCR(_activeToken, _debtToken);

        // maxBorrow needs to be denominated in debtTokens
        maxBorrow = (((assets - oFeeTokens) * 10_000) / MCR) * activeTokenPrice / 10**18;
    }

    function computeWithdrawAllowance(address _owner, uint _index)
        public
        view
        returns (uint apTokenMax, uint activeTokenMax)
    {
        if (safeManagerContract.getSafeStatus(_owner, _index) != 1) return (0, 0);

        CacheInit memory cacheInit;

        (
            cacheInit.owner,
            cacheInit.activeToken,
            cacheInit.debtToken
        ) = safeManagerContract.getSafeInit(_owner, _index);

        CacheVal memory cacheVal;

        (
            cacheVal.bal,   // apTokens
            cacheVal.mintFeeApplied,
            cacheVal.redemptionFeeApplied,
            cacheVal.debt // unactiveTokens
        ) = safeManagerContract.getSafeVal(_owner, _index);

        // First, find the ActivePool contract of the activeToken.
        address _activePool = safeManagerContract.getActivePool(cacheInit.activeToken);

        IERC4626 activePool = IERC4626(_activePool);

        // Second, get the pricePerShare for the _bal
        uint activeTokenBal = activePool.previewRedeem(cacheVal.bal);
        console.log("Active token bal: %s", activeTokenBal);

        if (cacheInit.debtToken == address(0)) return (cacheVal.bal, activeTokenBal);

        uint activeTokenPrice = priceFeedContract.getPrice(cacheInit.activeToken);
        console.log("activeToken price: %s", activeTokenPrice);
        uint debtTokenPrice = priceFeedContract.getPrice(cacheInit.debtToken);
        console.log("debtToken price: %s", debtTokenPrice);

        uint MCR = safeManagerContract.getActiveToDebtTokenMCR(
            cacheInit.activeToken,
            cacheInit.debtToken
        );

        uint locked = (cacheVal.debt * debtTokenPrice * MCR) / (10**18 * 10_000);
        console.log("Total locked ($): %s", locked);

        uint collateral = (activeTokenBal * activeTokenPrice) / 10**18;
        console.log("Safe collateral ($): %s", collateral);

        if (collateral <= locked) {
            return (0,0);
        } else {
            activeTokenMax = (collateral - locked).divPrecisely(activeTokenPrice);
            apTokenMax = activePool.previewMint(activeTokenMax);
        }
    }

    /**
     * @param _activeToken The activeToken posted as collateral.
     * @param _debtToken The debtToken to be issued.
     * @param _amount The amount of activeToken collateral.
     * @param _debtAmount The amount of debtTokens issued.
     */
    function computeCR(address _activeToken, address _debtToken, uint _amount, uint _debtAmount)
        public
        view
        returns (uint CR)
    {
        // First, find the ActivePool contract of the activeToken.
        address _activePool = safeManagerContract.getActivePool(_activeToken);
        IERC4626 activePool = IERC4626(_activePool);

        // Second, get the pricePerShare for the _bal
        uint assets = activePool.previewRedeem(_amount);

        uint activeTokenPrice = priceFeedContract.getPrice(_activeToken);
        uint debtTokenPrice = priceFeedContract.getPrice(_debtToken);
        CR = ((assets * activeTokenPrice) - originationFee)
            .divPrecisely(_debtAmount * debtTokenPrice).mulTruncate(10_000);
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