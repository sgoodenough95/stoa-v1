// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IERC4626.sol";
import "./interfaces/IVaultWrapper.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/ISafeManager.sol";

/**
 * @title Stable Controller
 * @notice
 *  Controller contract that directs stablecoins to yield venues (vaults).
 *  If yield has been earned, Keepers can call 'rebase()' and the Controller's
 *  receiptToken will adjust user balances accordingly.
 * @dev
 *  Interfaces with vault.
 *  Calls mint/burn function of USDST contract upon deposit/withdrawal.
 *  Calls 'changeSupply()' of USDST contract upon successful rebase.
 *  Drips (makes yield available) to Activator contract.
 */
contract StableController is Ownable {

    address safeOperations;
    address safeManager;
    address receiptToken;

    address public constant DAIAddress =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDCAddress =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /**
     * @dev
     *  Only accept one inputToken to begin with.
     *  Need to later adapt for stablecoins.
     */
    IERC20 public inputTokenContract;

    /**
     * @dev
     *  Only accept one yield venue per Controller (this contract) to begin with.
     *  For integrations that are not ERC4626-compatible (e.g., Aave), need to point to
     *  a ERC4626 wrapper.
     */
    IERC4626 public vault;

    /**
     * @dev Only one receiptToken per Controller (this contract).
     * @notice Rebasing (activated) Stoa token.
     */
    IActivated public receiptTokenContract;

    ISafeManager safeManagerContract = ISafeManager(safeManager);

    /**
     * @dev Boolean to pause receiving deposits.
     */
    bool public isReceivingInputs;

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
     * @dev Set initial values and approvals.
     */
    constructor() // address _vault,
    // address _stoaToken,
    // address _inputTokenContract
    {
        // vault = IERC4626(_vault);
        // stoaToken = IERC20(_stoaToken);
        // IActivated = IStoaStable(_stoaToken);
        // adrInputTokenContract = _inputTokenContract;
        // inputTokenContract = IERC20(_inputTokenContract);
        // token.approve(address(vault), type(uint).max);
    }

    /**
     * @notice Deposits dollar-pegged stablecoin into vault and issues Stoa (receipt) tokens.
     * @dev Callable either directly from user (custodial) or SafeOperations (non-custodial).
     * @param _depositor The owner of the receiptTokens.
     * @param _amount The amount of inputTokens to deposit.
     * @return shares Amount of shares added for Stoa's management.
     */
    function deposit(
        address _depositor,
        uint256 _amount
    )
        external nonReentrant returns (uint shares)
    {
        require(_amount > MIN_AMOUNT, "Controller: Amount too low");

        // Insert logic to convert stablecoin to optimise for the best yield.

        // Use _depositor in place of msg.sender to check balance of depositor if called
        // via SafeOperations contract.
        require(
            inputTokenContract.balanceOf(_depositor) >= _amount,
            "Controller: Insufficient funds"
        );

        // Approve _inputTokenContract first before initiating transfer

        SafeERC20.safeTransferFrom(
            inputTokenContract,
            _depositor,
            address(this),
            _amount
        );

        shares = vault.deposit(_amount, address(this));

        uint _mintFee = (_amount / 10_000) * mintFee;
        uint mintAmount = _amount - _mintFee;

        if (msg.sender == safeOperations) {
            receiptTokenContract.mint(safeManager, mintAmount);
        } else {
            receiptTokenContract.mint(msg.sender, mintAmount);
        }

        // Mint Stoa's share to Controller (for now).
        receiptTokenContract.mint(address(this), mintFee);
    }

    function withdraw(
        address _withdrawer,
        uint256 _amount
    ) external nonReentrant returns (uint amount) {
        require(_amount > MIN_AMOUNT, "Controller: Amount too low");

        // Burn sender's Stoa stablecoins.
        receiptTokenContract.burn(msg.sender, _amount);

        uint _redemptionFee = (_amount / 10_000) * redemptionFee;
        uint redemptionAmount = _amount - _redemptionFee;

        // Withdraw input token from Vault and send to withdrawer.
        uint _shares = vault.convertToShares(redemptionAmount);
        amount = vault.redeem(_shares, _withdrawer, address(this));
    }

    function rebase() external returns (
        uint yield,
        uint userYield,
        uint stoaYield
    ) {
        uint256 receiptTokenContractSupply = IERC20(receiptToken).totalSupply();
        if (receiptTokenContractSupply == 0) {
            return (0, 0, 0);
        }

        // Get Vault value.
        uint256 vaultValue = totalValue();

        // Can add logic for Keeper rewards here.

        // Update supply accordingly. Take 10% cut of yield.
        if (vaultValue > receiptTokenContractSupply) {
            yield = vaultValue - receiptTokenContractSupply;
            userYield = (yield / 10_000) * (10_000 - mgmtFee);
            stoaYield = yield - userYield;

            receiptTokenContract.changeSupply(vaultValue);
        }

        safeManagerContract.updateRebasingCreditsPerToken(receiptToken);
    }

    function totalValue() public view virtual returns (uint value) {
        value = vault.maxWithdraw(address(this));
    }
}