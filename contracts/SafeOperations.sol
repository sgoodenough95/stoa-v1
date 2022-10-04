// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IController.sol";
import "./interfaces/ISafeManager.sol";
import "./interfaces/IActivated.sol";

/**
 * @dev
 *  Stores Safe data in and makes calls to SafeManager contract.
 *  Calls mint/burn of 'unactivated' tokens upon borrow/repay.
 *  Can deposit Stoa tokens into StabilityPool contract.
 * @notice
 *  Contains user-operated functions for managing Safes.
 */
contract SafeOperations {

    address safeManager;

    ISafeManager safeManagerContract;

    mapping(address => address) public tokenToController;

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

    // Reentrancy Guard logic.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant()
    {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev
     *  Returns the controller for a given inputToken.
     *  TBD whether this is handled by a separate Router contract.
     * @return address The address of the target controller.
     */
    function getController(address _inputToken)
        external
        view
        returns (address)
    {
        return tokenToController[_inputToken];
    }

    /**
     * @dev
     *  Transfers inputTokens from caller to target Controller (unless inputToken is an activeToken,
     *  in which case transfers inputTokens directly to SafeManager).
     *  Require a separate function / add-on to allow borrowing also in one tx
     *  (or just call both functions ?)
     * @notice User-facing function for opening a Safe.
     * @param _inputToken The address of the inputToken. Must be supported.
     * @param _amount The amount of inputTokens to deposit.
     */
    function openSafe(address _inputToken, uint _amount)
        external
    {
        // E.g., _inputToken = DAI.
        if (isActiveToken[_inputToken] == false) {
            // First, check if a Controller exists for the inputToken.
            require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

            IController targetController = IController(tokenToController[_inputToken]);

            address _activeToken = targetController.getActiveToken();

            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.initializeSafe({
                _owner: msg.sender,
                _activeToken: _activeToken,
                _amount: _amount,   // Do not apply mintFee, hence stays as _amount.
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
        }
        // E.g., _inputToken = USDSTa.
        else {
            IERC20 inputToken = IERC20(_inputToken);

            // Approve _inputToken first before initiating transfer
            SafeERC20.safeTransferFrom(inputToken, msg.sender, safeManager, _amount);

            safeManagerContract.initializeSafe({
                _owner: msg.sender,
                // _inputToken is already an activeToken (e.g., USDSTa).
                _activeToken: _inputToken,
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
     * @param _inputToken The inputted token (e.g., DAI, USDSTa, etc.).
     * @param _index Identifier for the Safe.
     * @param _amount The amount to deposit.
     */
    function depositToSafe(address _inputToken, uint _index, uint _amount)
        external
    {
        // E.g., _inputToken = DAI.
        if (isActiveToken[_inputToken] == false) {
            require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

            IController targetController = IController(tokenToController[_inputToken]);

            address _activeToken = targetController.getActiveToken();

            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _activeToken: _activeToken,
                _amount: _amount,
                _add: true,
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
        }
        // E.g., _inputToken = USDSTa.
        else {
            IERC20 inputToken = IERC20(_inputToken);

            // Approve _inputToken first before initiating transfer
            SafeERC20.safeTransferFrom(inputToken, msg.sender, safeManager, _amount);

            safeManagerContract.adjustSafeBal({
                _owner: msg.sender,
                _index: _index,
                _activeToken: _inputToken,
                _amount: _amount,
                _add: true,
                _mintFeeApplied: _amount,
                _redemptionFeeApplied: 0
            });
        }
        // For now, do not accept unactiveTokens as inputTokens.
    }

    // function withdrawTokens(address _activeToken, address _inputToken, uint _index, uint _amount)
    //     external
    // {
    //     // XOR operation enforcing selection of activeToken or inputToken.
    //     require(
    //         _activeToken == address(0) && _inputToken != address(0) ||
    //         _activeToken != address(0) && _inputToken == address(0)
    //     );
    //     (address token, bool activated) = _activeToken == address(0)
    //         ? (_inputToken, false)
    //         : (_activeToken, true);
    //     require(tokenToController[token] != address(0), "SafeOps: Controller not found");

    //     withdrawTokens(activated, _index, _amount);
    // }

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

        IActivated activeTokenContract = IActivated(cacheInit.activeToken);

        // Safe bal is in creditBalances, so need to estimate equivalent token balance.
        uint tokenAmount = activeTokenContract.convertToAssets(_amount);

        (int feeCoverage, uint mintFeeChange, uint redemptionFeeChange) = computeFee(
            _activated,
            cacheVal.mintFeeApplied,
            cacheVal.redemptionFeeApplied,
            tokenAmount
        );

        // Locate the activeToken's Controller.
        address _targetController = tokenToController[cacheInit.activeToken];

        IERC20 activeTokenContractERC20 = IERC20(cacheInit.activeToken);

        // Transfer activeTokens to the Controller to be able to service the withdrawal.
        SafeERC20.safeTransferFrom(activeTokenContractERC20, safeManager, _targetController, tokenAmount);

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
    {

    }

    function repay(uint _amount)
        external
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
    {

    }

    function transferDebtTokens(
        address _debtToken,
        uint _index,
        uint _amount,
        uint _newIndex
    )
        external
    {

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
    function setController(address _inputToken, address _controller)
        external
    {
        tokenToController[_inputToken] = _controller;
    }
}