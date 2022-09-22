// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface ISafeManager {

    function openSafe(address _owner, address _receiptToken, uint _amount, uint _mintFeeApplied) external;

    function updateRebasingCreditsPerToken(address _inputToken) external view returns (uint);
}