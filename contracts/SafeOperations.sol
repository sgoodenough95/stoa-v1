// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IController.sol";
import "./interfaces/ISafeManager.sol";
import "./interfaces/IActivated.sol";

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
contract SafeOperations is ReentrancyGuard {

    address safeManager;

    ISafeManager safeManagerContract;

    mapping(address => address) public tokenToController;

    /**
     * @dev
     *  Later use for self-repaying loan logic.
     */
    mapping(address => bool) public isActiveToken;

    mapping(address => address) public activeToInputToken;

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
        uint locked;
    }

    uint cacheStatus;

    constructor(address _safeManager) {
        safeManager = _safeManager;
        safeManagerContract = ISafeManager(safeManager);
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

        // E.g., _token = DAI.
        if (validInputToken(_token)) {

            IController targetController = IController(tokenToController[_token]);

            address activeToken = targetController.getActiveToken();

            // Need to approve Vault spend for token first.
            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.initializeSafe({
                _owner: msg.sender,
                _activeToken: activeToken,
                _amount: _amount,   // Do not apply mintFee, hence stays as _amount.
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
        }
        // E.g., _token = USDSTa.
        else {
            require(validActiveToken(_token));

            IActivated activeToken = IActivated(_token);

            // Need to approve SafeOperations spend for token first.
            activeToken.transferFrom(msg.sender, safeManager, _amount);

            safeManagerContract.initializeSafe({
                _owner: msg.sender,
                _activeToken: _token,
                _amount: _amount,
                _mintFeeApplied: _amount,   // Mark mintFee as already paid for.
                _redemptionFeeApplied: 0
            });
        }
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

        // E.g., _token = DAI.
        if (validInputToken(_token)) {

            IController targetController = IController(tokenToController[_token]);

            address activeToken = targetController.getActiveToken();

            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _activeToken: activeToken,
                _amount: _amount,
                _add: true,
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
        }
        // E.g., _token = USDSTa.
        else {
            require(validActiveToken(_token));

            IActivated activeToken = IActivated(_token);

            // Need to approve SafeOperations spend for token first.
            activeToken.transferFrom(msg.sender, safeManager, _amount);

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _activeToken: _token,
                _amount: _amount,
                _add: true,
                _mintFeeApplied: _amount,
                _redemptionFeeApplied: 0
            });
        }
        // For now at least, do not allow unactiveToken deposits.
    }

    /**
     * @notice
     *  Safe owners can deposit either activeTokens or inputTokens (e.g., USDSTa or DAI).
     *  Can only deposit if the Safe supports that token.
     * @param _activated Boolean to indicate withdrawal of activeToken (true) or inputToken (false).
     * @param _index Identifier for the Safe.
     * @param _amount The amount to deposit.
     */
    function withdrawTokens(bool _activated, uint _index, uint _amount)
        external
        nonReentrant
    {
        CacheInit memory cacheInit;

        (
            cacheInit.owner,
            cacheInit.activeToken,
            cacheInit.debtToken
        ) = safeManagerContract.getSafeInit(msg.sender, _index);

        CacheVal memory cacheVal;

        (
            cacheVal.bal,  // credits
            cacheVal.mintFeeApplied,   // credits
            cacheVal.redemptionFeeApplied, // tokens
            cacheVal.debt, // tokens
            cacheVal.locked    // credits
        ) = safeManagerContract.getSafeVal(msg.sender, _index);

        require(msg.sender == cacheInit.owner, "SafeOps: Owner mismatch");
        require(_amount <= cacheVal.bal, "SafeOps: Insufficient Safe balance");

        IActivated activeToken = IActivated(cacheInit.activeToken);

        // Safe bal is in creditBalances, so need to estimate equivalent token balance.
        uint tokenAmount = activeToken.convertToAssets(_amount);

        (int feeCoverage, uint mintFeeChange, uint redemptionFeeChange) = computeFee(
            _activated,
            cacheVal.mintFeeApplied,
            cacheVal.redemptionFeeApplied,
            tokenAmount
        );

        // Locate the activeToken's Controller.
        address _targetController = tokenToController[cacheInit.activeToken];

        // Transfer activeTokens to the Controller to be able to service the withdrawal.
        // Need to approve SafeOperations spend (for SafeManager) for token first.
        activeToken.transferFrom(safeManager, _targetController, tokenAmount);

        IController targetController = IController(_targetController);

        // Transfer requested tokens to withdrawer.
        targetController.withdrawTokensFromSafe(msg.sender, _activated, _amount, feeCoverage);

        // Update Safe params.
        safeManagerContract.adjustSafeBal({
            _owner: msg.sender,
            _index: _index,
            _activeToken: cacheInit.activeToken,
            _amount: _amount,   // credits
            _add: false,
            _mintFeeApplied: mintFeeChange, // credits
            _redemptionFeeApplied: redemptionFeeChange  // tokens
        });

        // If Safe is empty then mark it as closed.
        if (_amount == cacheVal.bal) {
            safeManagerContract.setSafeStatus(msg.sender, _index, cacheInit.activeToken, 2);
        }
    }

    function initializeBorrow(uint _index, address _debtToken, uint _amount)
        external
    {
        
    }

    function borrow(uint _amount)
        external
        nonReentrant
    {

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
        // for which they are required to pay minting fees.
        feeCoverage = int(_amount - feeApplied);

        uint feeChange = feeCoverage > 0 ? feeApplied : _amount;
        (mintFeeChange, redemptionFeeChange) = _activated == true
            ? (feeChange, uint(0))
            : (0, feeChange);
    }

    /**
     * @dev Admin function to set the Controller of a given inputToken.
     */
    function setController(address _token, address _controller)
        external
    {
        tokenToController[_token] = _controller;
    }
}