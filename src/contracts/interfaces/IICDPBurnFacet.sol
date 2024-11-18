// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {BurnArgs} from "common/Args.sol";

interface IICDPBurnFacet {
    /**
     * @notice burns kopio to repay debt.
     * @notice restricted when caller differs from account or receiver.
     * @param args the burn arguments
     * @param prices price data
     */
    function burnKopio(BurnArgs memory args, bytes[] calldata prices) external payable;
}
