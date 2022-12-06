// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AppStorage } from "./libs/LibAppStorage.sol";
import { LibDiamond } from "./diamond/libs/LibDiamond.sol";
import { LibToken } from "./libs/LibToken.sol";

contract InitDiamond {
    AppStorage internal s;

    struct Args {
        address USDSTa;
        // address ETHSTa;
        address USDST;
        // address ETHST;
        address tDAI;
        // address tETH;
        address apUSDSTa;
        // address ETHSTaPool;
        address apUSDST;
        // address ETHSTPool;
        address vtDAI;
    }
    
    function init(Args memory _args) external {
        // Rebase opt-in
        LibToken._rebaseOptIn(_args.vtDAI);

        s.tokenToVenue[_args.tDAI]  = _args.vtDAI;
        s.tokenToAP[_args.USDSTa]   = _args.apUSDST;
        s.tokenToAP[_args.USDST]    = _args.apUSDST;

        // LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    }
}