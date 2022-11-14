// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;
import "../interfaces/IActivated.sol";

contract RebaseOpt {

    function rebaseOptIn(address _activeToken) public {
        IActivated(_activeToken).rebaseOptIn();
    }

    function rebaseOptOut(address _activeToken) public {
        IActivated(_activeToken).rebaseOptOut();
    }
}