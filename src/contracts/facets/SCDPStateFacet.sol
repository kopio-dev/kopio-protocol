// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ISCDPStateFacet} from "interfaces/ISCDPStateFacet.sol";
import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {Percents} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {scdp, sdi} from "scdp/State.sol";
import {SCDPAssetIndexes} from "scdp/Types.sol";

/**
 * @title SCDPStateFacet
 * @author the kopio project
 * @notice  This facet is used to view the state of the scdp.
 */
contract SCDPStateFacet is ISCDPStateFacet {
    using WadRay for uint256;
    using PercentageMath for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  Accounts                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISCDPStateFacet
    function getAccountDepositSCDP(address acc, address asset) external view returns (uint256) {
        return scdp().accountDeposits(acc, asset, cs().assets[asset]);
    }

    /// @inheritdoc ISCDPStateFacet
    function getAccountFeesSCDP(address acc, address asset) external view returns (uint256) {
        return scdp().accountFees(acc, asset, cs().assets[asset]);
    }

    /// @inheritdoc ISCDPStateFacet
    function getAccountTotalFeesValueSCDP(address acc) external view returns (uint256) {
        return scdp().accountTotalFeeValue(acc);
    }

    /// @inheritdoc ISCDPStateFacet
    function getAccountDepositValueSCDP(address acc, address asset) external view returns (uint256) {
        Asset storage cfg = cs().assets[asset];
        return cfg.toCollateralValue(scdp().accountDeposits(acc, asset, cfg), true);
    }

    /// @inheritdoc ISCDPStateFacet
    function getAccountTotalDepositsValueSCDP(address acc) external view returns (uint256) {
        return scdp().accountDepositsValue(acc, true);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Collaterals                                */
    /* -------------------------------------------------------------------------- */

    function getCollateralsSCDP() external view returns (address[] memory result) {
        return scdp().collaterals;
    }

    /// @inheritdoc ISCDPStateFacet
    function getDepositsSCDP(address collateral) external view returns (uint256) {
        return scdp().totalDepositAmount(collateral, cs().assets[collateral]);
    }

    /// @inheritdoc ISCDPStateFacet
    function getSwapDepositsSCDP(address collateral) external view returns (uint256) {
        return scdp().swapDepositAmount(collateral, cs().assets[collateral]);
    }

    /// @inheritdoc ISCDPStateFacet
    function getCollateralValueSCDP(address collateral, bool noFactors) external view returns (uint256) {
        Asset storage cfg = cs().assets[collateral];

        return cfg.toCollateralValue(scdp().totalDepositAmount(collateral, cfg), noFactors);
    }

    /// @inheritdoc ISCDPStateFacet
    function getTotalCollateralValueSCDP(bool noFactors) external view returns (uint256) {
        return scdp().totalCollateralValueSCDP(noFactors);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Kopios                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISCDPStateFacet
    function getKopiosSCDP() external view returns (address[] memory) {
        return scdp().kopios;
    }

    /// @inheritdoc ISCDPStateFacet
    function getAssetIndexesSCDP(address asset) external view returns (SCDPAssetIndexes memory) {
        return scdp().assetIndexes[asset];
    }

    /// @inheritdoc ISCDPStateFacet
    function getDebtSCDP(address kopio) external view returns (uint256) {
        Asset storage cfg = cs().assets[kopio];
        return cfg.toDynamic(scdp().assetData[kopio].debt);
    }

    /// @inheritdoc ISCDPStateFacet
    function getDebtValueSCDP(address kopio, bool noFactors) external view returns (uint256) {
        Asset storage cfg = cs().assets[kopio];
        return cfg.toDebtValue(cfg.toDynamic(scdp().assetData[kopio].debt), noFactors);
    }

    /// @inheritdoc ISCDPStateFacet
    function getTotalDebtValueSCDP(bool noFactors) external view returns (uint256) {
        return scdp().totalDebtValueAtRatioSCDP(Percents.HUNDRED, noFactors);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    MISC                                    */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISCDPStateFacet
    function getSwapEnabled(address kopio) external view returns (bool) {
        return scdp().isEnabled[kopio];
    }

    function getGlobalDepositEnabled(address asset) external view returns (bool) {
        return cs().assets[asset].isGlobalDepositable;
    }

    /// @inheritdoc ISCDPStateFacet
    function getRouteEnabled(address assetIn, address assetOut) external view returns (bool) {
        return scdp().isRoute[assetIn][assetOut];
    }

    function getGlobalCollateralRatio() public view returns (uint256) {
        uint256 collateralValue = scdp().totalCollateralValueSCDP(false);
        uint256 debtValue = sdi().effectiveDebtValue();
        if (collateralValue == 0) return 0;
        if (debtValue == 0) return type(uint256).max;
        return collateralValue.percentDiv(debtValue);
    }
}
