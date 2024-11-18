// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ISCDPConfigFacet} from "./ISCDPConfigFacet.sol";
import {ISCDPStateFacet} from "./ISCDPStateFacet.sol";
import {ISCDPFacet} from "./ISCDPFacet.sol";
import {ISCDPLiquidationFacet} from "./ISCDPLiquidationFacet.sol";
import {ISDIFacet} from "./ISDIFacet.sol";
import {ISwapFacet} from "./ISwapFacet.sol";
import {IICDPBurnFacet} from "./IICDPBurnFacet.sol";
import {IICDPConfigFacet} from "./IICDPConfigFacet.sol";
import {IICDPMintFacet} from "./IICDPMintFacet.sol";
import {IICDPCollateralFacet} from "./IICDPCollateralFacet.sol";
import {IICDPStateFacet} from "./IICDPStateFacet.sol";
import {IICDPLiquidationFacet} from "./IICDPLiquidationFacet.sol";
import {IICDPAccountStateFacet} from "./IICDPAccountStateFacet.sol";
import {IAuthorizationFacet} from "./IAuthorizationFacet.sol";
import {ISafetyCouncilFacet} from "./ISafetyCouncilFacet.sol";
import {ICommonConfigFacet} from "./ICommonConfigFacet.sol";
import {ICommonStateFacet} from "./ICommonStateFacet.sol";
import {IAssetStateFacet} from "./IAssetStateFacet.sol";
import {IAssetConfigFacet} from "./IAssetConfigFacet.sol";
import {IExtendedDiamondCutFacet} from "./IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "./IDiamondLoupeFacet.sol";
import {IDiamondStateFacet} from "./IDiamondStateFacet.sol";
import {IDataFacets} from "interfaces/IDataFacet.sol";
import {IBatchFacet} from "./IBatchFacet.sol";
import {IEmitted} from "./IEmitted.sol";

// solhint-disable-next-line no-empty-blocks
interface KopioCore is
    IEmitted,
    IExtendedDiamondCutFacet,
    IDiamondLoupeFacet,
    IDiamondStateFacet,
    IAuthorizationFacet,
    ICommonConfigFacet,
    ICommonStateFacet,
    IAssetConfigFacet,
    IAssetStateFacet,
    ISwapFacet,
    ISCDPFacet,
    ISCDPLiquidationFacet,
    ISCDPConfigFacet,
    ISCDPStateFacet,
    ISDIFacet,
    IICDPBurnFacet,
    ISafetyCouncilFacet,
    IICDPConfigFacet,
    IICDPMintFacet,
    IICDPStateFacet,
    IICDPCollateralFacet,
    IICDPAccountStateFacet,
    IICDPLiquidationFacet,
    IDataFacets,
    IBatchFacet
{}
