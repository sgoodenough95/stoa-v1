// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IController.sol";

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

    mapping(address => address) tokenToController;

    mapping(address => bool) isStoaToken;

    // Reentrancy Guard logic.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
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
    function getController(
        address _inputToken
    ) external view returns (address) {
        return tokenToController[_inputToken];
    }

    /**
     * @dev
     *  Transfers inputTokens from caller to target Controller (unless inputToken is a Stoa token,
     *  in which case transfers inputTokens (Stoa tokens) directly to SafeManager).
     * @notice User-facing function for opening a Safe.
     * @param _inputToken The address of the inputToken. Must be supported.
     * @param _amount The amount of inputTokens to deposit.
     */
    function openSafe(
        address _inputToken,
        uint _amount
    ) external {
        
        if (isStoaToken[_inputToken] == false) {
            require(tokenToController[_inputToken] != address(0), "SafeOps: Controller not found");

            address _targetController = tokenToController[_inputToken];

            IController targetController = IController(_targetController);

            targetController.deposit(msg.sender, _amount);
        } else {
            // If inputToken is a Stoa token.
            IERC20 inputToken = IERC20(_inputToken);

            // Approve _inputToken first before initiating transfer
            SafeERC20.safeTransferFrom(inputToken, msg.sender, safeManager, _amount);
        }

        // Set Safe params in SafeManager

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