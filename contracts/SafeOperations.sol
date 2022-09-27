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

    mapping(address => bool) public isReceiptToken;

    mapping(address => address) public receiptToInputToken;

    struct WithdrawCache {
        address owner;
        address receiptToken;
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
     * @dev Returns the controller for a given inputToken.
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
        if (isReceiptToken[_inputToken] == false) {
            // First, check if a Controller exists for the inputToken.
            require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

            address _targetController = tokenToController[_inputToken];

            IController targetController = IController(_targetController);

            address _receiptToken = targetController.getReceiptToken();

            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.openSafe(msg.sender, _receiptToken, _amount, 0, _amount);
        }
        // E.g., _inputToken = USDST.
        else {
            IERC20 inputToken = IERC20(_inputToken);

            // Approve _inputToken first before initiating transfer
            SafeERC20.safeTransferFrom(inputToken, msg.sender, safeManager, _amount);

            // _inputToken is already a receiptToken (e.g., USDST).
            safeManagerContract.openSafe(msg.sender, _inputToken, _amount, _amount, 0);
        }
    }

    function depositToSafe(address _inputToken, uint _index, uint _amount)
        external
    {
        // E.g., _inputToken = DAI.
        if (isReceiptToken[_inputToken] == false) {
            require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

            address _targetController = tokenToController[_inputToken];

            IController targetController = IController(_targetController);

            address _receiptToken = targetController.getReceiptToken();

            targetController.deposit(msg.sender, _amount, true);

            safeManagerContract.adjustSafeBal(msg.sender, _index, _receiptToken, _amount, true, 0, _amount);
        }
        // E.g., _inputToken = USDSTa.
        else {
            IERC20 inputToken = IERC20(_inputToken);

            // Approve _inputToken first before initiating transfer
            SafeERC20.safeTransferFrom(inputToken, msg.sender, safeManager, _amount);

            safeManagerContract.adjustSafeBal(msg.sender, _index, _inputToken, _amount, true, _amount, 0);
        }
        // For now, do not accept unactiveTokens as inputTokens.
    }

    /**
     * @dev
     *  Redemption fees do not apply where the user deposited DAI into the Safe.
     *  deposit(DAI) => (USDST = DAI + yield) => redeem(DAI + yield).
     */
    function withdrawInputTokens(address _inputToken, uint _index, uint _amount)
        external
    {
        require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

        // First, need to verify that the requested _amount of _inputToken can be
        // redeemed for the specified Safe AND that msg.sender is the owner.

        WithdrawCache memory withdrawCache;

        (
            withdrawCache.owner,
            withdrawCache.receiptToken,
            withdrawCache.debtToken,
            withdrawCache.bal,
            withdrawCache.mintFeeApplied,
            withdrawCache.redemptionFeeApplied,
            withdrawCache.debt,
            withdrawCache.locked,
            withdrawCache.status
        ) = safeManagerContract.getSafe(msg.sender, _index);

        require(msg.sender == withdrawCache.owner, "SafeOps: Owner mismatch");

        IActivated _receiptToken = IActivated(withdrawCache.receiptToken);

        uint inputTokenBal = _receiptToken.convertToAssets(withdrawCache.bal);
        require(_amount <= inputTokenBal, "SafeOps: Insufficient balance");

        // Second, transfer the correct amount of receiptTokens from SafeManager to Controller.
        // Recall that receiptTokens target a 1:1 correlation of inputTokens held in the Vault.
        // Approve _inputToken first before initiating transfer

        address _targetController = tokenToController[_inputToken];

        IERC20 receiptTokenContractERC20 = IERC20(withdrawCache.receiptToken);

        // Keep receiptTokens in Controller, to save on transfers (?)
        // Save 1 transfer: user deposits USDST to Controller (instead) and later redeems DAI.
        // Save 1 transfer: user deposits DAI to Controller (instead) and later redeems DAI.
        // Ans: NO, important to keep tokens in SafeManager in case of liquidations.
        SafeERC20.safeTransferFrom(receiptTokenContractERC20, safeManager, _targetController, _amount);

        IController targetController = IController(_targetController);

        // Withdraw inputToken.
        targetController.withdraw(msg.sender, _amount);

    }

    /**
     * @dev
     *  Mint fees do not apply where the user deposited USDT into the Safe.
     *  deposit(USDST) => (USDST) => redeem(USDST).
     */
    function withdrawReceiptTokens(address _receiptToken, uint _index, uint _amount)
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

    /**
     * @dev Admin function to set the Controller of a given inputToken.
     */
    function setController(
        address _inputToken,
        address _controller
    ) external {
        tokenToController[_inputToken] = _controller;
    }
}