// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IVaultWrapper.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/IUnactivated.sol";
import "./interfaces/ITreasury.sol";
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
 *  Stores vault tokens for yield venues, and apTokens for Safes.
 *  Can also provide one-way conversion of inputToken/activeToken to unactiveToken.
 *  Calls 'changeSupply()' of activeToken contract upon successful rebase.
 */
contract Controller is Ownable, RebaseOpt, Common, ReentrancyGuard {

    address public safeManager;

    /**
     * @notice
     *  Collects fees, backing tokens (+ yield) and
     *  liquidation gains.
     *  Allocates as necessary (e.g., depositing USDST backing
     *  tokens into the Curve USDST AcivePool).
     */
    address public treasury;
    
    address public activeToken;
    address public unactiveToken;
    address public inputToken;

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
     *  Only accept one yield venue per Controller to begin with.
     *  For integrations that are not ERC4626-compatible (e.g., Aave), need to point to
     *  a ERC4626 wrapper.
     */
    IERC4626 public vault;

    ITreasury treasuryContract;

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
        address _treasury,
        address _inputToken,
        address _activeToken,
        address _unactiveToken
    )
    {
        vault = IERC4626(_vault);

        treasury = _treasury;

        treasuryContract = ITreasury(_treasury);

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
     * @return shares Amount of share tokens minted (apTokens for Safes).
     */
    function deposit(address _depositor, uint256 _amount, bool _activated)
        external
        nonReentrant
        returns (uint shares)
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
        shares = vault.deposit(_amount, address(this), _depositor);
        console.log(
            "Controller deposited %s inputTokens to Vault on behalf of %s",
            _amount,
            _depositor
        );
        amountDeposited += _amount;

        uint _mintFee = computeFee(_amount, true);
        uint mintAmount = _amount - _mintFee;

        // E.g., DAI => USDSTa.
        if (_activated == true) {
            if (msg.sender == safeOperations) {
                activeTokenContract.mint(address(this), _amount);
                console.log(
                    "Minted %s activeTokens to Controller", _amount
                );

                IERC4626 activePool = IERC4626(
                    safeManagerContract.getActivePool(activeToken)
                );

                // Safe collateral is stored in its respective ActivePool contract.
                // Controller holds the apTokens for Safes.
                // Need to return shares for SafeOps to store apToken bal.
                // Uses SafeERC20 which might not work.
                shares = activePool.deposit(
                    _amount,
                    address(this)
                );

                // Do not apply mintFee if opening a Safe.
                mintAmount = _amount;
            } else {
                activeTokenContract.mint(msg.sender, mintAmount);
                console.log(
                    "Minted %s activeTokens to User", mintAmount
                );

                // Capture mintFee and send to Treasury.
                activeTokenContract.mint(treasury, _mintFee);
                console.log(
                    "Minted %s activeTokens to Treasury", _mintFee
                );
            }
        // E.g., DAI => USDST.
        } else {
            // Mint backing activeTokens to Treasury.
            activeTokenContract.mint(treasury, _amount);
            console.log(
                "Minted %s backing activeTokens to Treasury", _amount
            );

            // Treasury captures mintFee = _amount - mintAmount.
            treasuryContract.adjustBackingReserve({
                _wildToken: unactiveToken,
                _backingToken: activeToken,
                _amount: int(mintAmount)
            });
            console.log(
                "Treasury is backing %s unactiveTokens with activeTokens",
                mintAmount
            );

            // The user's unactiveTokens are backed by the activeTokens (sitting in the ActivePool)
            // minted to the Controller.
            unactiveTokenContract.mint(msg.sender, mintAmount);
            console.log(
                "Minted %s unactiveTokens to User", mintAmount
            );

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

        activeTokenContract.transferFrom(msg.sender, treasury, _amount);
        console.log(
            "Transferred %s activeTokens, for backing, from %s to Treasury",
            _amount,
            msg.sender
        );

        // Treasury captures mintFee = _amount - mintAmount.
        treasuryContract.adjustBackingReserve({
            _wildToken: unactiveToken,
            _backingToken: activeToken,
            _amount: int(mintAmount)
        });
        console.log(
            "Treasury is backing %s unactiveTokens with activeTokens",
            mintAmount
        );

        // Only users that do the conversion are permitted to convert back.
        // This reduces load on the Activator.
        unactiveRedemptionAllowance[msg.sender] += mintAmount;

        unactiveTokenContract.mint(msg.sender, mintAmount);
        console.log(
            "Minted %s unactiveTokens to User",
            mintAmount
        );
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
        require(
            unactiveTokenContractERC20.balanceOf(msg.sender) >= _amount,
            "Controller: Insufficient balance"
        );
        require(
            unactiveRedemptionAllowance[msg.sender] >= _amount,
            "Controller: Insufficient unactive token redemption allowance"
        );

        uint _redemptionFee = computeFee(_amount, false);
        redemptionAmount = _amount - _redemptionFee;

        // Burn the user's unactive tokens.
        unactiveTokenContract.burn(msg.sender, _amount);
        console.log(
            "Burned %s unactiveTokens from User",
            _amount
        );

        if (_activated == true) {
            // Later revisit to decide whether to apply a redemptionFee.
            activeTokenContract.transferFrom(treasury, msg.sender, redemptionAmount);
            console.log(
                "Transferred %s activeTokens from Treasury to User",
                redemptionAmount
            );
        } else {
            // Treasury retains redemptionFee amount of activeToken.
            activeTokenContract.burn(treasury, redemptionAmount);
            console.log(
                "Burned %s activeTokens from Treasury",
                redemptionAmount
            );

            // Withdraw input token from Vault and send to withdrawer.
            uint _shares = vault.convertToShares(redemptionAmount);
            vault.redeem(_shares, msg.sender, address(this));
            console.log(
                "Controller redeemed %s inputTokens / %s shares from Vault on behalf of %s",
                redemptionAmount,
                _shares,
                msg.sender
            );

            amountWithdrawn += _amount;
        }
        
        // No longer need to back the _amount of unactiveTokens burned.
        treasuryContract.adjustBackingReserve({
            _wildToken: unactiveToken,
            _backingToken: activeToken,
            _amount: int(_amount) * -1
        });
        console.log(
            "Treasury reduced backing of unactiveTokens by %s activeTokens",
            redemptionAmount
        );
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
        console.log(
            "Amount: %s redemptionAmount: %s fee: %s",
            _amount,
            redemptionAmount,
            _redemptionFee
        );

        // Stoa retains redemptionFee amount of activeToken.
        activeTokenContract.burn(msg.sender, redemptionAmount);
        console.log(
            "Burned %s activeTokens from caller",
            redemptionAmount
        );

        // Approve activeToken first before initiating transfer
        activeTokenContract.transferFrom(msg.sender, treasury, _redemptionFee);
        console.log(
            "Transferred %s activeTokens from %s to Treasury",
            _amount,
            msg.sender
        );

        // Withdraw input token from Vault and send to withdrawer.
        // Note that Controller retains _redemptionFee amount of vaultTokens
        // on behalf of the Treasury.
        uint _shares = vault.convertToShares(redemptionAmount);
        amount = vault.redeem(_shares, _withdrawer, address(this));
        console.log(
            "Controller redeemed %s inputTokens / %s shares from Vault on behalf of %s",
            redemptionAmount,
            _shares,
            _withdrawer
        );

        amountWithdrawn += _amount;
    }

    /**
     * @notice
     *  Function to withdraw inputTokens (e.g., DAI) from Safe.
     *  May need to later add third option for unactivated.
     * @param _withdrawer The address to send inputTokens to.
     * @param _activated Indicates if withdrawing activeTokens (if not, then inputTokens).
     * @param _shares The amount of apTokens.
     */
    function withdrawTokensFromSafe(
        address _withdrawer,
        bool _activated,
        uint _shares
        // int _feeCoverage
    )
        external
        onlySafeOps
        returns (uint activeTokens, uint inputTokens)   // uint fee
    {
        // fee = _feeCoverage <= 0 ? 0 : computeFee(uint(_feeCoverage), _activated);

        // redemptionAmount = _amount - fee;

        IERC4626 activePool = IERC4626(
            safeManagerContract.getActivePool(activeToken)
        );

        // Withdraw activeTokens from respective ActivePool.
        // Controller holds apTokens for Safes.
        // Controller retains fee amount of apTokens. (Need to later send to Treasury).

        if (_activated == true) {

            // _shares is apTokens, so no need to convertToShares beforehand.
            activeTokens = activePool.redeem(_shares, _withdrawer, address(this));
            console.log(
                "Redeemed %s shares for %s activeTokens and sent to Safe owner",
                _shares,
                activeTokens
            );

            // Add logic for transferring fee to Treasury.
            // if (fee > 0) {
            //     feeShares = 
            // }
        } else {

            activeTokens = activePool.redeem(_shares, address(this), address(this));
            console.log(
                "Redeemed %s shares for %s activeTokens and sent to Controller",
                _shares,
                activeTokens
            );

            // transferFrom to Controller already executed by SafeOps.
            // Stoa retains redemptionFee amount of activeToken (if not 0).
            activeTokenContract.burn(address(this), activeTokens);
            console.log(
                "Burned %s activeTokens from Controller",
                activeTokens
            );

            // Withdraw input token from Vault and send to withdrawer.
            _shares = vault.convertToShares(activeTokens);
            inputTokens = vault.redeem(_shares, _withdrawer, address(this));
            console.log(
                "Controller redeemed %s inputTokens / %s shares from Vault on behalf of %s",
                inputTokens,
                _shares,
                _withdrawer
            );

            amountWithdrawn += inputTokens;
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
        console.log(
            "Total value in Vault: %s",
            vaultValue
        );

        // Can add logic for Keeper rewards here.

        // Update supply accordingly. Take mgmtFee cut of yield.
        if (vaultValue > activeTokenContractSupply) {

            yield = vaultValue - activeTokenContractSupply;
            holderYield = (yield / 10_000) * (10_000 - mgmtFee);
            stoaYield = yield - holderYield;

            // We want the activeToken supply to mirror the size of the vault.
            activeTokenContract.changeSupply(activeTokenContractSupply + holderYield);
            console.log("Changed supply");
            if (stoaYield > 0) {
                activeTokenContract.mint(treasury, stoaYield);
                console.log(
                    "Minted %s management fee to Treasury",
                    stoaYield
                );
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

    function adjustMintFee(uint _newFee)
        external
        onlyOwner
    {
        mintFee = _newFee;
    }

    function adjustRedemptionFee(uint _newFee)
        external
        onlyOwner
    {
        redemptionFee = _newFee;
    }

    function adjustMgmtFee(uint _newFee)
        external
        onlyOwner
    {
        mgmtFee = _newFee;
    }

    function setSafeManager(address _safeManager)
        external
        onlyOwner
    {
        safeManager = _safeManager;
    }

    /**
     * @dev Required to call when withdrawing activeTokens, for e.g.
     * @notice _spender should only be Controller.
     */
    function approveToken(address _token, address _spender)
        external
    {
        IERC20 token = IERC20(_token);
        token.approve(_spender, type(uint).max);
    }
}