// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IVaultWrapper.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/IUnactivated.sol";
import "./interfaces/ISafeManager.sol";

/**
 * @notice
 *  Eventual aim is to generalise the Controller contract, potentially so that
 *  each instance will refer to the same implementation.
 */

/**
 * @title Controller
 * @notice
 *  Controller contract that directs inputTokens to a yield venue (vault).
 *  If yield has been earned, Keepers can call 'rebase()' and the Controller's
 *  activeToken will adjust user balances accordingly.
 * @dev
 *  Interfaces with vault.
 *  Calls mint/burn function of activeToken contract upon deposit/withdrawal.
 *  Can also provide one-way conversion of inputToken/activeToken to unactiveToken.
 *  Calls 'changeSupply()' of activeToken contract upon successful rebase.
 *  Drips (makes yield available) to Activator contract.
 */
contract Controller is Ownable {

    address safeOperations;
    address safeManager;
    address activeToken;
    address unactiveToken;

    /**
     * @dev
     *  Only accept one inputToken to begin with.
     *  Need to later adapt.
     */
    IERC20 public inputTokenContract;

    IERC20 public activeTokenContractERC20;
    IERC20 public unactiveTokenContractERC20;

    /**
     * @dev
     *  Only accept one yield venue per Controller (this contract) to begin with.
     *  For integrations that are not ERC4626-compatible (e.g., Aave), need to point to
     *  a ERC4626 wrapper.
     */
    IERC4626 public vault;

    /**
     * @dev Only one activeToken per Controller (this contract).
     * @notice Rebasing (activated) Stoa token.
     */
    IActivated public activeTokenContract;

    IUnactivated public unactiveTokenContract;

    ISafeManager safeManagerContract = ISafeManager(safeManager);

    /**
     * @dev Boolean to pause receiving deposits.
     */
    bool public isReceivingInputs;

    /**
     * @notice
     *  This is the Controller's reserve of activeTokens used to back
     *  unactiveTokens in the wild.
     *  These tokens are therefore untouchable.
     *  However, the interest generated is touchable.
     *  Similar to how Circle backs USDC with USD deposits and
     *  turns a profit from the interest generated on said deposits.
     */
    uint public activeTokenBackingReserve;

    /**
     * @notice Stat collection.
     */
    uint public amountDeposited;
    uint public amountWithdrawn;
    uint public accruedYield;

    /**
     * @notice Fees in basis points (e.g., 30 = 0.3%).
     */
    uint public mintFee = 30;
    uint public redemptionFee = 70;
    uint public mgmtFee = 1000;

    /**
     * @dev Minimum amounts.
     */
    uint256 MIN_AMOUNT = 20e18; // $20
    uint256 private dust = 1e16;

    // Reentrancy Guard logic.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier onlySafeOps()
    {
        require(msg.sender == safeOperations, "SafeManager: Only SafeOps can call");
        _;
    }

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
     * @dev Set initial values and approvals.
     */
    constructor(
        address _vault,
        address _inputToken,
        address _activeToken,
        address _unactiveToken
    )
    {
        vault = IERC4626(_vault);

        activeToken = _activeToken;

        unactiveToken = _unactiveToken;

        activeTokenContract = IActivated(activeTokenContract);

        unactiveTokenContract = IUnactivated(unactiveTokenContract);

        activeTokenContractERC20 = IERC20(activeToken);

        unactiveTokenContractERC20 = IERC20(unactiveToken);

        inputTokenContract = IERC20(_inputToken);

        activeTokenContractERC20.approve(address(this), type(uint).max);

        inputTokenContract.approve(address(vault), type(uint).max);
    }

    /**
     * @notice
     *  Deposits inputTokens into vault and issues Stoa (receipt) tokens.
     *  (receiptTokens may be activeTokens or unactiveTokens).
     * @dev
     *  Callable either directly from user (custodial) or SafeOperations (non-custodial).
     *  Accepts supported inputTokens.
     * @param _depositor The soon-to-be owner of the activeTokens or unactiveTokens.
     * @param _amount The amount of inputTokens to deposit.
     * @param _activated Tells the Controller whether to mint active or unactive tokens to the depositor.
     * @dev When called via SafeOperations, '_activated' will always be true.
     * @return mintAmount Amount of receiptTokens minted to caller.
     */
    function deposit(address _depositor, uint256 _amount, bool _activated)
        external
        nonReentrant
        returns (uint mintAmount)
    {
        require(_amount > MIN_AMOUNT, "Controller: Amount too low");

        // Need to later adapt to handle 2+ inputTokens and;
        // insert logic to convert inputTokens to optimise for the best yield.
        // As this logic may be ever-changing and unique, probably best to house in
        // a separate contract.

        // Use _depositor in place of msg.sender to check balance of depositor if called
        // via SafeOperations contract.
        require(
            inputTokenContract.balanceOf(_depositor) >= _amount,
            "Controller: Depositor has insufficient funds"
        );

        amountDeposited += _amount;

        // Approve _inputTokenContract first before initiating transfer
        // for vault to spend (transfer directly from depositor to vault)

        // Directly transfer from depositor to vault.
        // (Requires additional argument in deposit() of VaultWrapper: depositor).
        vault.deposit(_amount, address(this), _depositor);

        uint _mintFee = computeMintFee(_amount);
        mintAmount = _amount - _mintFee;

        // E.g., DAI => USDSTa.
        if (_activated == true) {
            if (msg.sender == safeOperations) {
                activeTokenContract.mint(safeManager, _amount);

                // Do not apply mintFee if opening a Safe.
                mintAmount = _amount;
            } else {
                activeTokenContract.mint(msg.sender, mintAmount);

                activeTokenContract.mint(address(this), mintFee);
            }

        // E.g., DAI => USDST.
        } else {
            activeTokenContract.mint(address(this), _amount);

            // The user's unactiveTokens are backed by the activeTokens minted
            // to the Controller.
            // This enables the Controller to engage in actions such as depositing
            // to the Stability Pool (with the mintFee plus yield earned).
            unactiveTokenContract.mint(msg.sender, mintAmount);

            // Unspendable tokens used to back unactiveTokens.
            activeTokenBackingReserve += mintAmount;
        }
    }

    /**
     * @notice
     *  Provides one-way conversion from active to unactive tokens.
     *  Simply transfers activeToken from user to this address and marks
     *  as unspendable.
     *  Excess activeTokens such as those generated from the yield are spendable.
     * @dev
     *  May need to experiement with transferFrom of rebasing token contract.
     * @param _amount The amount of activeTokens to convert.
     * @return mintAmount The amount of unactiveTokens received.
     */
    function activeToUnactive(uint _amount)
        external
        nonReentrant
        returns (uint mintAmount)
    {
        require(
            activeTokenContractERC20.balanceOf(msg.sender) >= _amount,
            "Controller: Insufficent active token balance"
        );

        uint _mintFee = computeMintFee(_amount);
        mintAmount = _amount - _mintFee;

        // Approve _inputTokenContract first before initiating transfer
        // SafeERC20 might fail on rebasing token contract.
        SafeERC20.safeTransferFrom(
            activeTokenContractERC20,
            msg.sender,
            address(this),
            _amount
        );

        // Controller captures mintFee amount + future yield earned.
        activeTokenBackingReserve += mintAmount;

        unactiveTokenContract.mint(msg.sender, mintAmount);
    }

    /**
     * @notice
     *  Enables caller to redeem underlying asset(s) for activeTokens.
     *  unactiveTokens can only be redeemed via the Activator contract.
     * @dev
     *  Need to handle allocation of inputTokens received by the user if
     *  managing multiple vaults.
     * @param _withdrawer The address to receive inputTokens.
     * @param _amount The amount of activeTokens transferred by the caller.
     */
    function withdraw(address _withdrawer, uint _amount)
        external
        nonReentrant
        returns (uint amount)
    {
        require(
            activeTokenContractERC20.balanceOf(msg.sender) >= _amount,
            "Controller: Insufficent active token balance"
        );
        require(_amount > MIN_AMOUNT, "Controller: Amount too low");

        uint _redemptionFee = computeRedemptionFee(_amount);
        uint redemptionAmount = _amount - _redemptionFee;

        // Approve _inputTokenContract first before initiating transfer
        // SafeERC20 might fail on rebasing token contract.
        // Transfer activeTokens to Controller first.
        SafeERC20.safeTransferFrom(
            activeTokenContractERC20,
            msg.sender,
            address(this),
            _amount
        );

        // Stoa retains redemptionFee amount of activeToken.
        activeTokenContract.burn(address(this), redemptionAmount);

        // Withdraw input token from Vault and send to withdrawer.
        uint _shares = vault.convertToShares(redemptionAmount);
        amount = vault.redeem(_shares, _withdrawer, address(this));

        amountWithdrawn += _amount;
    }

    function adminWithdraw(uint _amount, bool _max)
        external
        onlyOwner
    {
        uint _shares;
        if (_max == false) {
            _shares = vault.convertToShares(_amount);
            amountWithdrawn += _amount;
        }
        else {
            uint maxAmount = totalValue();
            _shares = vault.convertToShares(maxAmount);
            amountWithdrawn += maxAmount;
        }
        vault.redeem(_shares, address(this), address(this));
    }

    /**
     * @dev
     *  Separate withdraw function to handle redemptionFee logic.
     * @notice
     *  Function to withdraw inputTokens (e.g., DAI) from Safe.
     */
    function withdrawInputTokensFromSafe(address _withdrawer, uint _amount, uint _redemptionFeeApplied)
        external
        onlySafeOps
    {
        // Safe Manager transfers corresponding receiptTokens.
        // Controller retains receiptTokens for which redemption fees have not been applied.
    }

    /**
     * @dev
     *  Separate withdraw function to handle mintFee logic.
     * @notice
     *  Function to withdraw receiptTokens (e.g., USDSTa) from Safe.
     */
    function withdrawReceiptTokensFromSafe(address _withdrawer, uint _amount, uint _mintFeeApplied)
        external
        onlySafeOps
    {
        // Safe Manager transfers receiptTokens for which mint fees have not been applied.
    }

    function rebase()
        external
        returns (uint yield, uint userYield, uint stoaYield)
    {
        uint256 activeTokenContractSupply = IERC20(activeToken).totalSupply();
        if (activeTokenContractSupply == 0) {
            return (0, 0, 0);
        }

        // Get Vault value.
        uint256 vaultValue = totalValue();

        // Can add logic for Keeper rewards here.

        // Update supply accordingly. Take 10% cut of yield.
        if (vaultValue > activeTokenContractSupply) {

            // What logic here (?)
            yield = vaultValue - activeTokenContractSupply;
            userYield = (yield / 10_000) * (10_000 - mgmtFee);
            stoaYield = yield - userYield;

            // We want the activeToken supply to mirror the size of the vault.
            activeTokenContract.changeSupply(vaultValue);
        }

        // Not sure if needed, as SafeManager can get balance from activeToken contract (?)
        safeManagerContract.updateRebasingCreditsPerToken(activeToken);
    }

    function totalValue()
        public
        view
        virtual
        returns (uint value)
    {
        value = vault.maxWithdraw(address(this));
    }

    function computeMintFee(uint _amount)
        public
        view
        returns (uint _mintFee)
    {
        _mintFee = (_amount / 10_000) * mintFee;
    }

    function computeRedemptionFee(uint _amount)
        public
        view
        returns (uint _redemptionFee)
    {
        _redemptionFee = (_amount / 10_000) * redemptionFee;
    }

    function getReceiptToken()
        public
        view
        returns (address receiptToken)
    {
        receiptToken = activeToken;
    }

    // Needs amending if storing activeToken in Controller for Safes.
    function getExcessActiveTokenBalance()
        public
        view
        returns (uint excessActiveTokenBalance)
    {
        excessActiveTokenBalance =
            activeTokenContractERC20.balanceOf(address(this)) - activeTokenBackingReserve;
    }

    function adjustMintFee(uint _newFee) external {
        mintFee = _newFee;
    }

    function adjustRedemptionFee(uint _newFee) external {
        redemptionFee = _newFee;
    }

    function adjustMgmtFee(uint _newFee) external {
        mgmtFee = _newFee;
    }
}