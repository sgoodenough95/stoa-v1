// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibDiamond } from "../libs/LibDiamond.sol";
import { IERC173 } from "../interfaces/IERC173.sol";

contract OwnershipFacet is IERC173 {
    function transferOwnership(address _newOwner) public virtual override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    // addOwnership

    // removeOwnership (maybe requires 2/3).

    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }
}