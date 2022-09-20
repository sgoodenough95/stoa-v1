// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

/**
 * @title ERC4626 Interface
 * @author yearn.finance
 */
interface IVaultWrapper {
    error NoAvailableShares();
    error NotEnoughAvailableSharesForAmount();

    function vault() external view returns (address);

    function vaultTotalSupply() external view returns (uint256);
}
