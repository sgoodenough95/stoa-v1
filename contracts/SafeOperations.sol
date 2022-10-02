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

            address _targetController = tokenToController[_inputToken];

            IController targetController = IController(_targetController);

            address _activeToken = targetController.getActiveToken();

            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.openSafe({
                _owner: msg.sender,
                _activeToken: _activeToken,
                _amount: _amount,
                _mintFeeApplied: 0,
                _redemptionFeeApplied: _amount
            });
        }
        // E.g., _inputToken = USDST.
        else {
            IERC20 inputToken = IERC20(_inputToken);

            // Approve _inputToken first before initiating transfer
            SafeERC20.safeTransferFrom(inputToken, msg.sender, safeManager, _amount);

            safeManagerContract.openSafe({
                _owner: msg.sender,
                // _inputToken is already a activeToken (e.g., USDSTa).
                _activeToken: _inputToken,
                _amount: _amount,
                _mintFeeApplied: _amount,
                _redemptionFeeApplied: 0
            });
        }
    }

    function depositToSafe(address _inputToken, uint _index, uint _amount)
        external
    {
        // E.g., _inputToken = DAI.
        if (isActiveToken[_inputToken] == false) {
            require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

            address _targetController = tokenToController[_inputToken];

            IController targetController = IController(_targetController);

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
     * @dev
     *  Redemption fees do not apply where the user deposited DAI into the Safe.
     *  deposit(DAI) => (USDST = DAI + yield) => redeem(DAI + yield).
     * @param _inputToken The inputToken to be withdrawn.
     * @param _index The Safe to withdraw from.
     * @param _amount The amount of activeTokens to burn in credit balances (not token balance).
     * @param _minReceived Minimum amount of inputTokens to receive (before fees).
     */
    function withdrawInputTokens(address _inputToken, uint _index, uint _amount, uint _minReceived)
        external
    {
        require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

        // First, need to verify that the requested _amount of _inputToken can be
        // redeemed for the specified Safe AND that msg.sender is the owner.

        WithdrawCache memory withdrawCache;

        (
            withdrawCache.owner,
            withdrawCache.activeToken,  // USDSTa
            withdrawCache.debtToken,
            withdrawCache.bal,  // credits  // 1,000
            withdrawCache.mintFeeApplied,   // credits  // 0
            withdrawCache.redemptionFeeApplied, // tokens   // 1,000
            withdrawCache.debt, // tokens
            withdrawCache.locked,
            withdrawCache.status
        ) = safeManagerContract.getSafe(msg.sender, _index);

        require(msg.sender == withdrawCache.owner, "SafeOps: Owner mismatch");
        require(_amount <= withdrawCache.bal, "SafeOps: Insufficient Safe balance");

        IActivated activeTokenContract = IActivated(withdrawCache.activeToken);

        // Safe bal is in creditBalances, so need to estimate equivalent token balance.
        uint tokenAmount = activeTokenContract.convertToAssets(_amount);
        require(
            _minReceived >= tokenAmount,
            "SafeOps: Estimated tokens to receive is less than required amount"
        );

        // If > 0, means that the user is redeeming |redemptionFeeCoverage| amount of activeTokens,
        // for which they are obliged to pay redemption fees.   // 1,500 - 1,000 = 500
        int redemptionFeeCoverage = int(tokenAmount - withdrawCache.redemptionFeeApplied);

        // Second, transfer the correct amount of activeTokens from SafeManager to Controller.
        // Recall that activeTokens target a 1:1 correlation of inputTokens held in the Vault.
        // Approve _inputToken first before initiating transfer

        address _targetController = tokenToController[_inputToken];

        IERC20 activeTokenContractERC20 = IERC20(withdrawCache.activeToken);

        SafeERC20.safeTransferFrom(activeTokenContractERC20, safeManager, _targetController, tokenAmount);

        IController targetController = IController(_targetController);

        targetController.withdrawInputTokensFromSafe({
            _withdrawer: msg.sender,
            _amount: _amount,
            _redemptionFeeCoverage: redemptionFeeCoverage
        });

        uint redemptionFeeChange;
        if (redemptionFeeCoverage >= 0) {
            // _redemptionFeeApplied = 0 in Safe.
            redemptionFeeChange = withdrawCache.redemptionFeeApplied;
        } else {
            // E.g., 1,500 - 1,000 = 500.
            redemptionFeeChange = withdrawCache.redemptionFeeApplied - tokenAmount;
        }

        // Lastly, update Safe params. If Safe is empty then mark it as closed (?)
        safeManagerContract.adjustSafeBal({
            _owner: msg.sender,
            _index: _index,
            _activeToken: withdrawCache.activeToken,
            _amount: _amount,   // credits
            _add: false,
            _mintFeeApplied: 0, // credits
            _redemptionFeeApplied: redemptionFeeChange  // tokens
        });

        if (_amount == withdrawCache.bal) {
            safeManagerContract.setSafeStatus(msg.sender, _index, withdrawCache.activeToken, 2);
        }
    }

    /**
     * @dev
     *  Mint fees do not apply where the user deposited USDT into the Safe.
     *  deposit(USDST) => (USDST) => redeem(USDST).
     * @param _activeToken The inputToken to be withdrawn.
     * @param _index The Safe to withdraw from.
     * @param _amount The amount of activeTokens to burn in credit balances (not token balance).
     */
    function withdrawActiveTokens(address _activeToken, uint _index, uint _amount)
        external
    {
        require(tokenToController[_activeToken] != address(0), "SafeOps: Controller not found");

        // First, need to verify that the requested _amount of _inputToken can be
        // redeemed for the specified Safe AND that msg.sender is the owner.

        WithdrawCache memory withdrawCache;

        (
            withdrawCache.owner,
            withdrawCache.activeToken,  // USDSTa
            withdrawCache.debtToken,
            withdrawCache.bal,  // credits  // 1,000
            withdrawCache.mintFeeApplied,   // credits  // 0
            withdrawCache.redemptionFeeApplied, // tokens   // 1,000
            withdrawCache.debt, // tokens
            withdrawCache.locked,
            withdrawCache.status
        ) = safeManagerContract.getSafe(msg.sender, _index);

        require(msg.sender == withdrawCache.owner, "SafeOps: Owner mismatch");
        require(_activeToken == withdrawCache.activeToken, "SafeOps: activeToken mismatch");
        require(_amount <= withdrawCache.bal, "SafeOps: Insufficient Safe balance");

        IActivated activeTokenContract = IActivated(_activeToken);

        // If > 0, means that the user is "minting" |mintFeeCoverage| amount of activeTokens,
        // for which they are obliged to pay minting fees.   // 1,500 - 1,000 = 500
        int mintFeeCoverage = int(_amount - withdrawCache.mintFeeApplied);

        address _targetController = tokenToController[_activeToken];

        IERC20 activeTokenContractERC20 = IERC20(withdrawCache.activeToken);

        // Safe bal is in creditBalances, so need to estimate equivalent token balance.
        uint tokenAmount = activeTokenContract.convertToAssets(_amount);

        SafeERC20.safeTransferFrom(activeTokenContractERC20, safeManager, _targetController, tokenAmount);

        IController targetController = IController(_targetController);

        targetController.withdrawActiveTokensFromSafe({
            _withdrawer: msg.sender,
            _amount: _amount,
            _mintFeeCoverage: mintFeeCoverage
        });

        uint mintFeeChange;
        if (mintFeeCoverage >= 0) {
            // _redemptionFeeApplied = 0 in Safe.
            mintFeeChange = withdrawCache.mintFeeApplied;
        } else {
            // E.g., 1,500 - 1,000 = 500.
            mintFeeChange = withdrawCache.redemptionFeeApplied - _amount;
        }

        // Lastly, update Safe params. If Safe is empty then mark it as closed (?)
        safeManagerContract.adjustSafeBal({
            _owner: msg.sender,
            _index: _index,
            _activeToken: withdrawCache.activeToken,
            _amount: _amount,   // credits
            _add: false,
            _mintFeeApplied: mintFeeChange, // credits
            _redemptionFeeApplied: 0  // tokens
        });

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

    /**
     * @dev Admin function to set the Controller of a given inputToken.
     */
    function setController(address _inputToken, address _controller)
        external
    {
        tokenToController[_inputToken] = _controller;
    }
}