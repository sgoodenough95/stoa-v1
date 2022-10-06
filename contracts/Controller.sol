// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IVaultWrapper.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/IUnactivated.sol";
import "./interfaces/ISafeManager.sol";
import { RebaseOpt } from "./utils/RebaseOpt.sol";
import { Common } from "./utils/Common.sol";

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
contract Controller is Ownable, RebaseOpt, Common, ReentrancyGuard {

    address safeManager;
    address activeToken;
    address unactiveToken;
    address inputToken;

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

    mapping(address => uint) private unactiveRedemptionAllowance;

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
    uint public yieldAccrued;
    uint public holderYieldAccrued;
    uint public stoaYieldAccrued;

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

        inputToken = _inputToken;

        activeTokenContract = IActivated(activeToken);

        unactiveTokenContract = IUnactivated(unactiveToken);

        activeTokenContractERC20 = IERC20(activeToken);

        unactiveTokenContractERC20 = IERC20(unactiveToken);

        inputTokenContract = IERC20(_inputToken);

        activeTokenContractERC20.approve(address(this), type(uint).max);

        inputTokenContract.approve(address(vault), type(uint).max);
    }

    /**
     * @notice
     *  Deposits inputTokens into vault and issues Stoa tokens.
     * @dev
     *  Callable either directly from user (non-custodial) or SafeOperations (custodial).
     *  Accepts supported inputTokens.
     * @param _depositor The soon-to-be owner of the activeTokens or unactiveTokens.
     * @param _amount The amount of inputTokens to deposit.
     * @param _activated Tells the Controller whether to mint active or unactive tokens to the depositor.
     * @dev When called via SafeOperations, '_activated' will always be true.
     * @return mintAmount Amount of Stoa tokens minted to caller.
     */
    function deposit(address _depositor, uint256 _amount, bool _activated)
        external
        nonReentrant
        returns (uint mintAmount)
    {
        require(_amount > MIN_AMOUNT, "Controller: Amount too low");

        // Use _depositor in place of msg.sender to check balance of depositor if called
        // via SafeOperations contract.
        require(
            inputTokenContract.balanceOf(_depositor) >= _amount,
            "Controller: Depositor has insufficient funds"
        );

        // Approve _inputTokenContract first before initiating transfer
        // for vault to spend (transfer directly from depositor to vault)

        // Directly transfers from depositor to vault.
        // (Requires additional argument in deposit() of VaultWrapper: depositor).
        vault.deposit(_amount, address(this), _depositor);
        amountDeposited += _amount;

        uint _mintFee = computeFee(_amount, true);
        mintAmount = _amount - _mintFee;

        // E.g., DAI => USDSTa.
        if (_activated == true) {
            if (msg.sender == safeOperations) {
                activeTokenContract.mint(safeManager, _amount);

                // Do not apply mintFee if opening a Safe.
                mintAmount = _amount;
            } else {
                activeTokenContract.mint(msg.sender, mintAmount);

                // Capture mintFee.
                activeTokenContract.mint(address(this), _mintFee);
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

            unactiveRedemptionAllowance[msg.sender] += mintAmount;
        }
    }

    /**
     * @notice
     *  Provides conversion from active to unactive tokens.
     *  Simply transfers activeToken from user to this address and marks
     *  as unspendable.
     *  Excess activeTokens such as those generated from the yield are spendable.
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

        uint _mintFee = computeFee(_amount, true);
        mintAmount = _amount - _mintFee;

        activeTokenContract.transferFrom(msg.sender, address(this), _amount);

        // Controller captures mintFee amount + future yield earned.
        activeTokenBackingReserve += mintAmount;

        // Only users that do the conversion are permitted to convert back.
        unactiveRedemptionAllowance[msg.sender] += mintAmount;

        unactiveTokenContract.mint(msg.sender, mintAmount);
    }

    /**
     * @notice
     *  Function that allows for unactive redemptions for either the
     *  activeToken or inputToken.
     *  Motivation in having is to reduce the load off the Activator.
     * @param _amount The amount of unactiveTokens to redeem.
     * @param _activated Indicates whether the user wants to receive activeTokens.
     * @return redemptionAmount The amount of tokens to receive.
     */
    function unactiveRedemption(uint _amount, bool _activated)
        external
        nonReentrant
        returns (uint redemptionAmount)
    {
        // Enables Stoa to stabilise the unactiveToken price if need be.
        redemptionAmount = _amount;
        if (msg.sender != owner()) {
            require(
                unactiveRedemptionAllowance[msg.sender] >= _amount,
                "Controller: Insufficient unactive token redemption allowance"
            );
            require(
                unactiveTokenContractERC20.balanceOf(msg.sender) >= _amount,
                "Controller: Insufficient balance"
            );

            uint _redemptionFee = computeFee(_amount, false);
            redemptionAmount = _amount - _redemptionFee;
        }

        // Burn the user's unactive tokens.
        unactiveTokenContract.burn(msg.sender, _amount);

        if (_activated == true) {
            activeTokenContract.transfer(msg.sender, redemptionAmount);

        } else {
            // Stoa retains redemptionFee amount of activeToken.
            activeTokenContract.burn(address(this), redemptionAmount);

            // Withdraw input token from Vault and send to withdrawer.
            uint _shares = vault.convertToShares(redemptionAmount);
            vault.redeem(_shares, msg.sender, address(this));

            amountWithdrawn += _amount;
        }
        
        // No longer need to back the _amount of unactiveTokens burned.
        activeTokenBackingReserve -= _amount;
    }

    /**
     * @notice
     *  Enables caller to redeem underlying asset(s) by burning activeTokens.
     *  unactiveTokens can only be redeemed via the Activator contract if the
     *  caller has an insufficient unactive redemption allowance.
     * @dev
     *  May later need to adapt if handling multiple inputTokens (e.g., DAI + USDC).
     * @param _withdrawer The address to receive inputTokens.
     * @param _amount The amount of activeTokens transferred by the caller (in tokens).
     * @return amount The amount of inputTokens redeemed from the vault.
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

        uint _redemptionFee = computeFee(_amount, false);
        uint redemptionAmount = _amount - _redemptionFee;

        // Approve _inputTokenContract first before initiating transfer
        activeTokenContract.transferFrom(msg.sender, address(this), _amount);

        // Stoa retains redemptionFee amount of activeToken.
        activeTokenContract.burn(address(this), redemptionAmount);

        // Withdraw input token from Vault and send to withdrawer.
        uint _shares = vault.convertToShares(redemptionAmount);
        amount = vault.redeem(_shares, _withdrawer, address(this));

        amountWithdrawn += _amount;
    }

    /**
     * @notice
     *  Admin function to withdraw tokens from Vault.
     *  May be used in case of emergency or a better yield opportunity
     *  exists for the inputToken.
     */
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
     * @notice
     *  Function to withdraw inputTokens (e.g., DAI) from Safe.
     * @param _withdrawer The address to send inputTokens to.
     * @param _activated Indicates if withdrawing activeTokens (if not, then inputTokens).
     * @param _amount The amount of activeTokens to exchange for inputTokens (in tokens, not credits).
     * @param _feeCoverage The amount for which to charge minting or redemption fees (if negative).
     */
    function withdrawTokensFromSafe(address _withdrawer, bool _activated, uint _amount, int _feeCoverage)
        external
        onlySafeOps
        returns (uint amount)
    {
        uint fee = _feeCoverage <= 0 ? 0 : computeFee(_amount, _activated);

        amount = _amount - fee;

        if (_activated == true) {
            activeTokenContract.transfer(_withdrawer, amount);
        } else {
            // transferFrom to Controller already executed by SafeOps.
            // Stoa retains redemptionFee amount of activeToken (if not 0).
            activeTokenContract.burn(address(this), amount);

            // Withdraw input token from Vault and send to withdrawer.
            uint _shares = vault.convertToShares(amount);
            amount = vault.redeem(_shares, _withdrawer, address(this));

            amountWithdrawn += _amount;
        }
    }

    function rebase()
        external
        returns (uint yield, uint holderYield, uint stoaYield)
    {
        uint activeTokenContractSupply = IERC20(activeToken).totalSupply();
        if (activeTokenContractSupply == 0) {
            return (0, 0, 0);
        }

        // Get Vault value.
        uint vaultValue = totalValue();

        // Can add logic for Keeper rewards here.

        // Update supply accordingly. Take mgmtFee cut of yield.
        if (vaultValue > activeTokenContractSupply) {

            yield = vaultValue - activeTokenContractSupply;
            holderYield = (yield / 10_000) * (10_000 - mgmtFee);
            stoaYield = yield - holderYield;

            // We want the activeToken supply to mirror the size of the vault.
            activeTokenContract.changeSupply(activeTokenContractSupply + holderYield);
            if (stoaYield > 0) {
                activeTokenContract.mint(address(this), stoaYield);
            }

            yieldAccrued += yield;
            holderYieldAccrued += holderYield;
            stoaYieldAccrued += stoaYield;
        }
    }

    function totalValue()
        public
        view
        virtual
        returns (uint value)
    {
        value = vault.maxWithdraw(address(this));
    }

    function computeFee(uint _amount, bool _mint)
        public
        view
        returns (uint fee)
    {
        uint _fee = _mint == true ? mintFee : redemptionFee;
        fee = (_amount / 10_000) * _fee;
    }

    function computeRedemptionFee(uint _amount)
        public
        view
        returns (uint _redemptionFee)
    {
        _redemptionFee = (_amount / 10_000) * redemptionFee;
    }

    function getActiveToken()
        public
        view
        returns (address _activeToken)
    {
        _activeToken = activeToken;
    }

    function getInputToken()
        public
        view
        returns (address _inputToken)
    {
        _inputToken = inputToken;
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