// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {cs} from "common/State.sol";
import {scdp} from "scdp/State.sol";
import {ArbDeployAddr} from "kopio/info/ArbDeployAddr.sol";

contract AssetPayload is ArbDeployAddr {
    address public immutable newAssetAddr;

    constructor(address _newAssetAddr) {
        newAssetAddr = _newAssetAddr;
    }

    function executePayload() external {
        require(cs().assets[newAssetAddr].ticker != bytes32(0), "Invalid asset address or asset not added to protocol");

        scdp().isRoute[kSOLAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kSOLAddr] = true;

        scdp().isRoute[kETHAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kETHAddr] = true;

        scdp().isRoute[kBTCAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kBTCAddr] = true;

        scdp().isRoute[oneAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][oneAddr] = true;

        scdp().isRoute[kGBPAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kGBPAddr] = true;

        scdp().isRoute[kEURAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kEURAddr] = true;

        scdp().isRoute[kJPYAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kJPYAddr] = true;

        scdp().isRoute[kXAUAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kXAUAddr] = true;

        scdp().isRoute[kXAGAddr][newAssetAddr] = true;
        scdp().isRoute[newAssetAddr][kXAGAddr] = true;
    }
}
