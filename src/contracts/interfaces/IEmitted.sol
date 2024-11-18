// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {err} from "common/Errors.sol";
import {DTypes} from "diamond/Types.sol";
import {MEvent} from "icdp/Event.sol";
import {SEvent} from "scdp/Event.sol";
import {Multi} from "interfaces/IKopioMulticall.sol";
import {VEvent} from "vault/Events.sol";

interface IEmitted is err, DTypes, MEvent, SEvent, VEvent, Multi {
    /// @dev Unable to deploy the contract.
    error DeploymentFailed();

    /// @dev Unable to initialize the contract.
    error InitializationFailed();

    error BatchRevertSilentOrCustomError(bytes innerError);
    error CreateProxyPreview(address proxy);
    error CreateProxyAndLogicPreview(address proxy, address implementation);
    error ArrayLengthMismatch(uint256 proxies, uint256 implementations, uint256 datas);
    error DeployerAlreadySet(address, bool);
}
