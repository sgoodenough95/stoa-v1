// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IController.sol";
import "./interfaces/IActivated.sol";
import "./interfaces/ISafeOperations.sol";

/**
 * @dev
 *  Stores Safe data.
 *  Each Safe supports one type of collateral asset.
 *  Stores liquidation logic. Keepers can liquidate Safes where their CR is breached.
 * @notice
 *  Contract that owns Safes. Holds 'activated' and 'unactivated' Stoa tokens held by users in Safes.
 */
contract SafeManager {

    address public safeOperations;

    ISafeOperations safeOperationsContract = ISafeOperations(safeOperations);

    /**
     * @dev
     *  Counter that increments each time an address opens a Safe.
     *  Enables us to differentiate between Safes of the same user that
     *  have the same receiptToken but not debtToken.
     *  E.g., Safe 1: BTCST => USDSTu, Safe 2: BTCST => ETHSTu.
     *  Reason being, for now, only allow one debtToken per Safe.
     */
    mapping(address => uint) currentSafeIndex;

    /**
     * @dev Safe owner => safeIndex => Safe.
     */
    mapping(address => mapping(uint => Safe)) public safe;

    /**
     * @dev receiptToken => rebasingCreditsPerToken.
     *  Motivation in having is to update Safe bals upon rebase (?)
     */
    mapping(address => uint) public rebasingCreditsPerReceiptToken;

    /**
     * @dev receiptToken => Max Collateralization Ratio.
     */
    mapping(address => uint) public receiptTokenToMCR;

    /**
     * @dev Start with one available debtToken per receiptToken to begin with.
     */
    mapping(address => address[]) public receiptTokenToSupportedDebtTokens;

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation
    }

    // One Safe supports one type of receiptToken and one type of debtToken.
    struct Safe {
        address owner;
        // // E.g., USDST
        address receiptToken;
        // E.g., USDSTu
        // Might not necessarily know this when opening a Safe.
        address debtToken;
        // receiptToken creditBalance;
        uint bal;
        // Increments only if depositing activeToken.
        uint mintFeeApplied;
        uint redemptionFeeApplied;
        // Balance of the debtToken.
        uint debt;
        // Amount of receiptTokens locked as collateral.
        uint locked;
        uint index;
        Status status;
    }

    modifier onlySafeOps()
    {
        require(msg.sender == safeOperations, "SafeManager: Only SafeOps can call");
        _;
    }

    constructor(
        address _safeOperations
    ) {
        safeOperations = _safeOperations;
    }

    /**
     * @notice Function to verify Safe's receiptToken.
     * @return bool Expected receiptToken is correct.
     */
    function getSafe(
        address _owner,
        uint _index
    ) external view returns (address, address, address, uint, uint, uint, uint, uint, uint) {
        return (
            safe[_owner][_index].owner,
            safe[_owner][_index].receiptToken,
            safe[_owner][_index].debtToken,
            safe[_owner][_index].bal,
            safe[_owner][_index].mintFeeApplied,
            safe[_owner][_index].redemptionFeeApplied,
            safe[_owner][_index].debt,
            safe[_owner][_index].locked,
            uint(safe[_owner][_index].status)
        );
    }

    function openSafe(
        address _owner,
        address _receiptToken,
        uint _amount,
        uint _mintFeeApplied,
        uint _redemptionFeeApplied
    )
        external
        onlySafeOps
    {
        // First, find the user's current index.
        uint _index = currentSafeIndex[_owner];

        // Now set Safe params.
        safe[_owner][_index].owner = _owner;
        safe[_owner][_index].receiptToken = _receiptToken;
        safe[_owner][_index].bal = _amount;
        safe[_owner][_index].mintFeeApplied = _mintFeeApplied;
        safe[_owner][_index].redemptionFeeApplied = _redemptionFeeApplied;
        safe[_owner][_index].index = _index;
        safe[_owner][_index].status = Status(1);

        currentSafeIndex[_owner] += 1;
    }

    /**
     * @dev Safe balance setter, called only by SafeOperations
     * @param _owner The owner of the Safe.
     * @param _index The Safe's index.
     * @param _amount The amount of receiptTokens.
     * @param _add Boolean to indicate if _amount subtracts or adds to Safe balance.
     */
    function adjustSafeBal(
        address _owner,
        uint _index,
        address _receiptToken,
        uint _amount,
        bool _add,
        uint _mintFeeApplied,
        uint _redemptionFeeApplied
    )
        external
        onlySafeOps
    {
        require(safe[_owner][_index].receiptToken == _receiptToken, "SafeManager: receiptToken mismatch");
        if (_add == true) {
            safe[_owner][_index].bal += _amount;
            safe[_owner][_index].mintFeeApplied += _mintFeeApplied;
            safe[_owner][_index].redemptionFeeApplied += _redemptionFeeApplied;
        } else {
            require(safe[_owner][_index].bal >= _amount, "SafeManager: Safe cannot have negative balance");
            // When debtTokens are issued, it moves the proportionate amount from 'bal' to 'locked'.
            // Therefore, only consider 'bal' for now.
            safe[_owner][_index].bal -= _amount;
            // Fees
        }
    }

    /**
     * @dev Safe debt setter, called only by SafeOperations.
     * @param _owner The owner of the Safe.
     * @param _inputToken Parameter for identifying the Safe.
     * @param _amount The amount of debtTokens.
     * @param _add Boolean to indicate if _amount subtracts or adds to Safe debt.
     */
    function adjustSafeDebt(
        address _owner,
        address _inputToken,
        uint _amount,
        bool _add
    ) external onlySafeOps {
        if (_add == true) {
            // Insert logic to handle max debt allowance.
            safe[_owner][_inputToken].bal += _amount;
        } else {

        }
    }

    /**
     * @dev Safe Status setter, called only by SafeOperations.
     * @param _owner The owner of the Safe.
     * @param _inputToken Parameter for identifying the Safe.
     * @param _num Parameter for selecting the Status.
     */
    function setSafeStatus(
        address _owner,
        address _inputToken,
        uint _num
    ) external onlySafeOps {
        safe[_owner][_inputToken].status = Status(_num);
    }

    function approveToken(address _token, address _spender) external {
        IERC20 token = IERC20(_token);
        token.approve(_spender, type(uint).max);
    }

    /**
     * @dev
     *  Function for updating token balances upon rebase.
     *  Only callable from the target Controller of the receiptToken.
     */
    function updateRebasingCreditsPerToken(
        address _receiptToken
    ) external returns (uint) {
        address _controller = safeOperationsContract.getController(_receiptToken);
        require(msg.sender == _controller, "Only target Controller can call");
        return rebasingCreditsPerReceiptToken[_receiptToken] = IActivated(_receiptToken).rebasingCreditsPerToken();
    }
}