// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./utils/StableMath.sol";

/**
 * @title USDST Token Contract
 * @author stoa.money
 * @dev
 *  Stores functions for minting/burning tokens upon deposit/withdrawal and changing supply
 *  upon yield generation. Also provides functions for seamlessly interacting with
 *  relevant Stability Pool.
 * @notice
 *  Rebasing token that overrides standard ERC20 methods to provide scalable rebasing functionality.
 */
contract USDST is ERC20 {
    using StableMath for uint;

    address public controller;

    uint public _totalSupply;

    uint private _rebasingCredits;

    /**
     * @dev Akin to Price Per Share.
     */
    uint private _rebasingCreditsPerToken;

    uint private constant MAX_SUPPLY = ~uint128(0);

    mapping(address => mapping(address => uint256)) private _allowances;

    /**
     * @notice
     *  Credit balances can be though of as your 'actual' balance. It does not rebase, and
     *  changes upon mint, burn, and transfer.
     */
    mapping(address => uint256) public _creditBalances;

    event TotalSupplyUpdated(
        uint totalSupply,
        uint rebasingCredits,
        uint rebasingCreditsPerToken
    );

    /**
     * @dev Reentrancy guard logic.
     */
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
     * @dev Verifies that the caller is the correct Controller contract.
     */
    modifier onlyController() {
        require(msg.sender == controller, "USDST: Caller is not Controller");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _rebasingCreditsPerToken = 1e18;
    }    

    /**
     * @return _totalSupply The total supply of USDST.
     */
    function totalSupply() public view override returns (uint) {
        return _totalSupply;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _account Address to query the balance of.
     * @return
     *  A uint256 representing the amount of base units owned by the
     *  specified address.
     */
    function balanceOf(
        address _account
    ) public view override returns (uint) {
        if (_creditBalances[_account] == 0) return 0;

        // As the denominator decreases, the result (balance) increases.
        return _creditBalances[_account].divPrecisely(_rebasingCreditsPerToken);
    }

    function allowance(
        address _owner,
        address _spender
    ) public view override returns (uint) {
        return _allowances[_owner][_spender];
    }

    /**
     * @return _rebasingCreditsPerToken Low resolution rebasingCreditsPerToken.
     */
    function rebasingCreditsPerToken() public view returns (uint) {
        return _rebasingCreditsPerToken;
    }

    /**
     * @return _rebasingCredits Low resolution total number of rebasing credits.
     */
    function rebasingCredits() public view returns (uint) {
        return _rebasingCredits;
    }

    /**
     * @dev Gets the credits balance of the specified address.
     * @param _account The address to query the balance of.
     * @return _creditBalances[_account]
     *  A uint256 representing the amount of credit balances owned by the
     *  specified address.
     */
    function creditBalancesOf(
        address _account
    ) public view returns (uint) {
        return _creditBalances[_account];
    }

    /**
     * @dev Helper function to convert credit balance to token balance.
     * @param _creditBalance The credit balance to convert.
     * @return assets The amount converted to token balance.
     */
    function convertToAssets(
        uint _creditBalance
    ) public view returns (uint assets) {
        require(_creditBalance > 0, "USDST: Credit balance must be greater than 0");
        assets = _creditBalance.divPrecisely(_rebasingCreditsPerToken);
    }

    /**
     * @dev Transfer tokens to a specified address.
     * @param _to the address to transfer to.
     * @param _value the amount to be transferred.
     * @return true on success.
     */
    function transfer(
        address _to,
        uint _value
    ) public override returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(_value <= balanceOf(msg.sender), "Transfer greater than balance");

        _executeTransfer(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);

        return true;
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param _from The address you want to send tokens from.
     * @param _to The address you want to transfer to.
     * @param _value The amount of tokens to be transferred.
     */
    function transferFrom(
        address _from,
        address _to,
        uint _value
    ) public override returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(_value <= balanceOf(msg.sender), "Transfer greater than balance");

        _allowances[_from][msg.sender] -= _value;

        _executeTransfer(_from, _to, _value);

        emit Transfer(_from, _to, _value);

        return true;
    }

    /**
     * @dev
     *  Approve the passed address to spend the specified amount of tokens
     *  on behalf of msg.sender. This method is included for ERC20
     *  compatibility. `increaseAllowance` and `decreaseAllowance` should be
     *  used instead.
     *
     *  Changing an allowance with this method brings the risk that someone
     *  may transfer both the old and the new allowance - if they are both
     *  greater than zero - if a transfer transaction is mined before the
     *  later approve() call is mined.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(
        address _spender,
        uint _value
    ) public override returns (bool) {
        _allowances[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);

        return true;
    }

    /**
     * @dev
     *  Increase the amount of tokens that an owner has allowed to `_spender`.
     *  This method should be used instead of approve() to avoid the double
     *  approval vulnerability described above.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to increase the allowance by.
     * @return bool Indicates successful operation.
     */
    function increaseAllowance(
        address _spender,
        uint _value
    ) public override returns (bool) {
        _allowances[msg.sender][_spender] += _value;

        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);

        return true;
    }

    /**
     * @dev
     *  Decrease the amount of tokens that an owner has allowed to `_spender`.
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to decrease the allowance by.
     * @return bool Indicates successful operation.
     */
    function decreaseAllowance(
        address _spender,
        uint _value
    ) public override returns (bool) {
        if (_allowances[msg.sender][_spender] <= _value) {
            _allowances[msg.sender][_spender] = 0;
        }
        else {
            _allowances[msg.sender][_spender] -= _value;
        }

        emit Approval(msg.sender, _spender, _allowances[msg.sender][_spender]);

        return true;
    }

    /**
     * @dev Mints new tokens, increasing totalSupply.
     * @param _account The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(
        address _account,
        uint _amount
    ) external {
        _mint(_account, _amount);
    }

    /**
     * @dev Burns tokens, decreasing totalSupply.
     * @param _account The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function burn(
        address _account,
        uint _amount
    ) external {
        _burn(_account, _amount);
    }

    /**
     * @dev
     *  Modify the supply without minting new tokens. This uses a change in
     *  the exchange rate between "credits" and OUSD tokens to change balances.
     * @param _newTotalSupply New total supply of USDST.
     * @return _totalSupply The new calibrated total supply of USDST.
     */
    function changeSupply(
        uint _newTotalSupply
    ) external nonReentrant returns (uint) {
        require(_totalSupply > 0, "Cannot increase 0 supply");

        if (_totalSupply == _newTotalSupply) {
            emit TotalSupplyUpdated(
                _totalSupply,
                _rebasingCredits,
                _rebasingCreditsPerToken
            );
            return 0;
        }

        if (_newTotalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        } else {
            _totalSupply = _newTotalSupply;
        }

        _rebasingCreditsPerToken = _rebasingCredits.divPrecisely(_totalSupply);
        require(_rebasingCreditsPerToken > 0, "Invalid change in supply");

        // Recalibrating _totalSupply to satisfy credits.
        _totalSupply = _rebasingCredits.divPrecisely(_rebasingCreditsPerToken);
        
        emit TotalSupplyUpdated(_totalSupply, _rebasingCredits, _rebasingCreditsPerToken);

        return _totalSupply;
    }

    function sendToPool() external {}

    function returnFromPool() external {}

    /**
     *  @dev Admin function to set Controller address.
     */
    function setController(
        address _controller
    ) external returns (bool) {
        controller = _controller;
        return true;
    }

    /**
     * @dev Creates `_amount` tokens and assigns them to `_account`, increasing
     * the total supply.
     */
    function _mint(
        address _account,
        uint _amount
    ) internal override nonReentrant {
        require(_account != address(0), "Mint to zero address");

        uint creditAmount = _amount.mulTruncate(_rebasingCreditsPerToken);
        _creditBalances[_account] += creditAmount;

        _rebasingCredits += creditAmount;

        _totalSupply += _amount;
        require(_totalSupply < MAX_SUPPLY, "Max supply reached");

        emit Transfer(address(0), _account, _amount);
    }
    
    /**
     * @dev Destroys `_amount` tokens from `_account`, reducing the
     * total supply.
     */
    function _burn(
        address _account,
        uint256 _amount
    ) internal override nonReentrant {
        require(_account != address(0), "Burn from the zero address");
        if (_amount == 0) {
            return;
        }

        // bool isNonRebasingAccount = _isNonRebasingAccount(_account);
        uint creditAmount = _amount.mulTruncate(_rebasingCreditsPerToken);
        uint currentCredits = _creditBalances[_account];

        // Remove the credits, burning rounding errors
        if (
            currentCredits == creditAmount || currentCredits - 1 == creditAmount
        ) {
            // Handle dust from rounding
            _creditBalances[_account] = 0;
        } else if (currentCredits > creditAmount) {
            _creditBalances[_account] -=
                creditAmount;
        } else {
            revert("Remove exceeds balance");
        }

        _rebasingCredits -= creditAmount;

        _totalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);
    }

    /**
     * @dev Update the count of non rebasing credits in response to a transfer
     * @param _from The address you want to send tokens from.
     * @param _to The address you want to transfer to.
     * @param _value Amount of OUSD to transfer
     */
    function _executeTransfer(
        address _from,
        address _to,
        uint _value
    ) internal {
        uint creditsExchanged = _value.mulTruncate(_rebasingCreditsPerToken);

        _creditBalances[_from] -= creditsExchanged;
        _creditBalances[_to] += creditsExchanged;
    }
}