// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AppStorage } from "./libs/LibAppStorage.sol";
import { LibDiamond } from "./diamond/libs/LibDiamond.sol";

contract InitDiamond {
    AppStorage internal s;

    struct Args {
        address USDSTa;
        // address ETHSTa;
        address USDST;
        // address ETHST;
        address tDAI;
        // address tETH;
        address USDSTaPool;
        // address ETHSTaPool;
        address USDSTPool;
        // address ETHSTPool;
        address tDAIVenue;
    }
    
    function init(Args memory _args) external {
        s.tokenToVenue[_args.tDAI]  = _args.tDAIVenue;
        s.tokenToAP[_args.USDSTa]   = _args.USDSTaPool;
        s.tokenToAP[_args.USDST]    = _args.USDSTPool;

        // LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    }
}