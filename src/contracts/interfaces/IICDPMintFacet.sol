// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {MintArgs} from "common/Args.sol";

interface IICDPMintFacet {
    function mintKopio(MintArgs memory args, bytes[] calldata prices) external payable;
}
