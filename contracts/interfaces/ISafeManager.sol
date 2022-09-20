// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

interface ISafeManager {

    function updateRebasingCreditsPerToken(address _inputToken) external view returns (uint);
}