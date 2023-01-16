// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AppStorage } from "./libs/LibAppStorage.sol";
import { LibDiamond } from "./diamond-core/libs/LibDiamond.sol";
import { LibToken } from "./libs/LibToken.sol";

contract InitDiamond {
    AppStorage internal s;

    struct Args {
        address USDSTa;
        address USDST;
        address DAI;
        address yvDAI;
    }
    
    function init(Args memory _args) external {
        // Rebase opt-in
        LibToken._rebaseOptIn(_args.USDSTa);

        s._refTokens[_args.USDSTa].underlyingToken  = _args.DAI;
        s._refTokens[_args.USDSTa].vaultToken       = _args.yvDAI;
        s._refTokens[_args.USDSTa].unactiveToken    = _args.USDST;

        s._refTokens[_args.USDSTa].enabled      = 1;
        s._underlyingTokens[_args.DAI].enabled  = 1;
        s._vaultTokens[_args.yvDAI].enabled     = 1;

        s.minDeposit[_args.DAI]     = 20 * 10**18;
        s.minWithdraw[_args.DAI]    = 50 * 10**18;

        s.mintFee[_args.USDSTa]         = 30;
        s.redemptionFee[_args.USDSTa]   = 30;
        s.conversionFee[_args.USDSTa]   = 10;
    }
}