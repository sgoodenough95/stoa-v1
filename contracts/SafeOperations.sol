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

    struct WithdrawCache {
        address owner;
        address activeToken;
        address debtToken;
        uint bal;
        uint mintFeeApplied;
        uint redemptionFeeApplied;
        uint debt;
        uint locked;
        uint status;
    }

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

    /**
     * @notice
     *  Safe owners can deposit either activeTokens or inputTokens (e.g., USDSTa or DAI).
     *  Can only deposit if the Safe supports that token.
     * @param _inputToken The inputToken (e.g., DAI) to withdraw (address(0) if not).
     * @param _activeToken The activeToken (e.g., USDSTa) to withdraw (address(0) if not).
     * @param _index Identifier for the Safe.
     * @param _amount The amount to deposit.
     */
    function withdrawTokens(address _activeToken, address _inputToken, uint _index, uint _amount)
        external
    {
        // XOR operation enforcing selection of activeToken or inputToken.
        require(
            _activeToken == address(0) && _inputToken != address(0) ||
            _activeToken != address(0) && _inputToken == address(0)
        );
        (address token, bool activated) = _activeToken == address(0)
            ? (_inputToken, false)
            : (_activeToken, true);
        require(tokenToController[token] != address(0), "SafeOps: Controller not found");

        // First, need to verify that the requested _amount of _inputToken can be
        // redeemed for the specified Safe AND that msg.sender is the owner.

        WithdrawCache memory withdrawCache;

        (
            withdrawCache.owner,
            withdrawCache.activeToken,
            withdrawCache.debtToken,
            withdrawCache.bal,  // credits
            withdrawCache.mintFeeApplied,   // credits
            withdrawCache.redemptionFeeApplied, // tokens
            withdrawCache.debt, // tokens
            withdrawCache.locked,
            withdrawCache.status
        ) = safeManagerContract.getSafe(msg.sender, _index);

        require(msg.sender == withdrawCache.owner, "SafeOps: Owner mismatch");
        require(_amount <= withdrawCache.bal, "SafeOps: Insufficient Safe balance");

        IActivated activeTokenContract = IActivated(withdrawCache.activeToken);

        uint feeApplied = token == _activeToken
            ? withdrawCache.mintFeeApplied
            : withdrawCache.redemptionFeeApplied;

        // If > 0, means that the user is "minting" or redeeming |feeCoverage| amount of tokens,
        // for which they are required to pay minting fees.
        int feeCoverage = int(_amount - feeApplied);

        address _targetController = tokenToController[_activeToken];

        IERC20 activeTokenContractERC20 = IERC20(withdrawCache.activeToken);

        // Safe bal is in creditBalances, so need to estimate equivalent token balance.
        uint tokenAmount = activeTokenContract.convertToAssets(_amount);

        uint feeChange = computeFeeChange(
            feeCoverage,
            feeApplied,
            tokenAmount
        );

        SafeERC20.safeTransferFrom(activeTokenContractERC20, safeManager, _targetController, tokenAmount);

        IController targetController = IController(_targetController);

        targetController.withdrawTokensFromSafe(msg.sender, activated, _amount, feeCoverage);

        (uint mintFeeChange, uint redemptionFeeChange) = token == _activeToken
            ? (feeChange, uint(0))
            : (0, feeChange);

        // Lastly, update Safe params.
        safeManagerContract.adjustSafeBal({
            _owner: msg.sender,
            _index: _index,
            _activeToken: withdrawCache.activeToken,
            _amount: _amount,   // credits
            _add: false,
            _mintFeeApplied: mintFeeChange, // credits
            _redemptionFeeApplied: redemptionFeeChange  // tokens
        });

        // If Safe is empty then mark it as closed.
        if (_amount == withdrawCache.bal) {
            safeManagerContract.setSafeStatus(msg.sender, _index, withdrawCache.activeToken, 2);
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

    function computeFeeChange(int _coverage, uint _feeApplied, uint _amount)
        internal
        pure
        returns (uint feeChange)
    {
        feeChange = _coverage > 0 ? _feeApplied : _amount;
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