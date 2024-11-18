// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;
import {IERC165} from "vendor/IERC165.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {IKopio} from "interfaces/IKopio.sol";
import {IKopioIssuer} from "interfaces/IKopioIssuer.sol";
import {IONE} from "interfaces/IONE.sol";

import {Strings} from "vendor/Strings.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";

import {err, id} from "common/Errors.sol";
import {Asset, OraclePrice} from "common/Types.sol";
import {Role, Percents, Constants} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {pushPrice} from "periphery/Helpers.sol";

import {scdp} from "scdp/State.sol";
import {ms} from "icdp/State.sol";

// solhint-disable code-complexity
library ValidationsConfig {
    using PercentageMath for uint256;
    using PercentageMath for uint16;
    using Strings for bytes32;

    function validatePriceDeviationPct(uint16 _deviationPct) internal pure {
        if (_deviationPct > Percents.MAX_DEVIATION) {
            revert err.INVALID_ORACLE_DEVIATION(_deviationPct, Percents.MAX_DEVIATION);
        }
    }

    function validateMinDebtValue(uint256 _minDebtValue) internal pure {
        if (_minDebtValue > Constants.MAX_MIN_DEBT_VALUE) {
            revert err.INVALID_MIN_DEBT(_minDebtValue, Constants.MAX_MIN_DEBT_VALUE);
        }
    }

    function validateFeeRecipient(address _feeRecipient) internal pure {
        if (_feeRecipient == address(0)) revert err.INVALID_FEE_RECIPIENT(_feeRecipient);
    }

    function validateOraclePrecision(uint256 _decimalPrecision) internal pure {
        if (_decimalPrecision < Constants.MIN_ORACLE_DECIMALS) {
            revert err.INVALID_PRICE_PRECISION(_decimalPrecision, Constants.MIN_ORACLE_DECIMALS);
        }
    }

    function validateCoverThreshold(uint256 _coverThreshold, uint256 _mcr) internal pure {
        if (_coverThreshold > _mcr) {
            revert err.INVALID_COVER_THRESHOLD(_coverThreshold, _mcr);
        }
    }

    function validateCoverIncentive(uint256 _coverIncentive) internal pure {
        if (_coverIncentive > Percents.MAX_LIQ_INCENTIVE || _coverIncentive < Percents.HUNDRED) {
            revert err.INVALID_COVER_INCENTIVE(_coverIncentive, Percents.HUNDRED, Percents.MAX_LIQ_INCENTIVE);
        }
    }

    function validateMCR(uint256 mcr, uint256 lt) internal pure {
        if (mcr < Percents.MIN_MCR) {
            revert err.INVALID_MCR(mcr, Percents.MIN_MCR);
        }
        // this should never be hit, but just in case
        if (lt >= mcr) {
            revert err.INVALID_MCR(mcr, lt);
        }
    }

    function validateLT(uint256 lt, uint256 mcr) internal pure {
        if (lt < Percents.MIN_LT || lt >= mcr) {
            revert err.INVALID_LIQ_THRESHOLD(lt, Percents.MIN_LT, mcr);
        }
    }

    function validateMLR(uint256 ratio, uint256 threshold) internal pure {
        if (ratio < threshold) {
            revert err.MLR_LESS_THAN_LT(ratio, threshold);
        }
    }

    function validateAddAssetArgs(
        address asset,
        Asset memory _config
    ) internal view returns (string memory symbol, string memory tickerStr, uint8 decimals) {
        if (asset == address(0)) revert err.ZERO_ADDRESS();

        symbol = IERC20(asset).symbol();
        if (cs().assets[asset].exists()) revert err.ASSET_EXISTS(err.ID(symbol, asset));

        tickerStr = _config.ticker.toString();
        if (_config.ticker == 0) revert err.INVALID_TICKER(err.ID(symbol, asset), tickerStr);

        decimals = IERC20(asset).decimals();
        validateDecimals(asset, decimals);
    }

    function validateUpdateAssetArgs(
        address assetAddr,
        Asset memory _config
    ) internal view returns (string memory symbol, string memory tickerStr, Asset storage asset) {
        if (assetAddr == address(0)) revert err.ZERO_ADDRESS();

        symbol = IERC20(assetAddr).symbol();
        asset = cs().assets[assetAddr];

        if (!asset.exists()) revert err.INVALID_ASSET(assetAddr);

        tickerStr = _config.ticker.toString();
        if (_config.ticker == 0) revert err.INVALID_TICKER(err.ID(symbol, assetAddr), tickerStr);
    }

    function validateAsset(address asset, Asset memory _config) internal view returns (bool) {
        validateCollateral(asset, _config);
        validateKopio(asset, _config);
        validateSCDPDepositable(asset, _config);
        validateSCDPKopio(asset, _config);
        validatePushPrice(asset);
        validateLiqConfig(asset);
        return true;
    }

    function validateCollateral(address asset, Asset memory _config) internal view returns (bool isCollateral) {
        if (_config.isCollateral) {
            validateCFactor(asset, _config.factor);
            validateLiqIncentive(asset, _config.liqIncentive);
            return true;
        }
    }

    function validateSCDPDepositable(address asset, Asset memory _config) internal view returns (bool isGlobalDepositable) {
        if (_config.isGlobalDepositable) {
            validateCFactor(asset, _config.factor);
            return true;
        }
    }

    function validateKopio(address asset, Asset memory _config) internal view returns (bool isKopio) {
        if (_config.isKopio) {
            validateDFactor(asset, _config.dFactor);
            validateFees(asset, _config.openFee, _config.closeFee);
            validateContracts(asset, _config.share);
            return true;
        }
    }

    function validateSCDPKopio(address asset, Asset memory _config) internal view returns (bool isSwapMintable) {
        if (_config.isSwapMintable) {
            validateFees(asset, _config.swapInFee, _config.swapOutFee);
            validateFees(asset, _config.protocolFeeShareSCDP, _config.protocolFeeShareSCDP);
            validateLiqIncentive(asset, _config.liqIncentiveSCDP);
            return true;
        }
    }

    function validateSDICoverAsset(address asset) internal view returns (Asset storage cfg) {
        cfg = cs().assets[asset];
        if (!cfg.exists()) revert err.INVALID_ASSET(asset);
        if (cfg.isCoverAsset) revert err.ASSET_ALREADY_ENABLED(id(asset));
        validatePushPrice(asset);
    }

    function validateContracts(address assetAddr, address shareAddr) internal view {
        IERC165 asset = IERC165(assetAddr);
        if (!asset.supportsInterface(type(IONE).interfaceId) && !asset.supportsInterface(type(IKopio).interfaceId)) {
            revert err.INVALID_KOPIO(id(assetAddr));
        }
        if (!IERC165(shareAddr).supportsInterface(type(IKopioIssuer).interfaceId)) {
            revert err.INVALID_SHARE(id(shareAddr), id(assetAddr));
        }
        if (!IKopio(assetAddr).hasRole(Role.OPERATOR, address(this))) {
            revert err.INVALID_KOPIO_OPERATOR(id(assetAddr), address(this), IKopio(assetAddr).getRoleMember(Role.OPERATOR, 0));
        }
    }

    function validateDecimals(address asset, uint8 dec) internal view {
        if (dec == 0) {
            revert err.INVALID_DECIMALS(id(asset), dec);
        }
    }

    function validateVaultAssetDecimals(address asset, uint8 dec) internal view {
        if (dec == 0) {
            revert err.INVALID_DECIMALS(id(asset), dec);
        }
        if (dec > 18) revert err.INVALID_DECIMALS(id(asset), dec);
    }

    function validateCFactor(address asset, uint16 _cFactor) internal view {
        if (_cFactor > Percents.HUNDRED) {
            revert err.INVALID_CFACTOR(id(asset), _cFactor, Percents.HUNDRED);
        }
    }

    function validateDFactor(address asset, uint16 _dFactor) internal view {
        if (_dFactor < Percents.HUNDRED) {
            revert err.INVALID_DFACTOR(id(asset), _dFactor, Percents.HUNDRED);
        }
    }

    function validateFees(address asset, uint16 _fee1, uint16 _fee2) internal view {
        if (_fee1 + _fee2 > Percents.HUNDRED) {
            revert err.INVALID_FEE(id(asset), _fee1 + _fee2, Percents.HUNDRED);
        }
    }

    function validateLiqIncentive(address asset, uint16 incentive) internal view {
        if (incentive > Percents.MAX_LIQ_INCENTIVE || incentive < Percents.MIN_LIQ_INCENTIVE) {
            revert err.INVALID_LIQ_INCENTIVE(id(asset), incentive, Percents.MIN_LIQ_INCENTIVE, Percents.MAX_LIQ_INCENTIVE);
        }
    }

    function validateLiqConfig(address asset) internal view {
        Asset storage cfg = cs().assets[asset];
        if (cfg.isKopio) {
            address[] memory icdpCollaterals = ms().collaterals;
            for (uint256 i; i < icdpCollaterals.length; i++) {
                address collateralAddr = icdpCollaterals[i];
                Asset storage collateral = cs().assets[collateralAddr];
                validateLiquidationMarket(collateralAddr, collateral, asset, cfg);
                validateLiquidationMarket(asset, cfg, collateralAddr, collateral);
            }
        }

        if (cfg.isCollateral) {
            address[] memory minteds = ms().kopios;
            for (uint256 i; i < minteds.length; i++) {
                address assetAddr = minteds[i];
                Asset storage kopio = cs().assets[assetAddr];
                validateLiquidationMarket(asset, cfg, assetAddr, kopio);
                validateLiquidationMarket(assetAddr, kopio, asset, cfg);
            }
        }

        if (cfg.isGlobalDepositable) {
            address[] memory scdpKopios = scdp().kopios;
            for (uint256 i; i < scdpKopios.length; i++) {
                address scdpKopio = scdpKopios[i];
                Asset storage kopio = cs().assets[scdpKopio];
                validateLiquidationMarket(asset, cfg, scdpKopio, kopio);
                validateLiquidationMarket(scdpKopio, kopio, asset, cfg);
            }
        }

        if (cfg.isSwapMintable) {
            address[] memory scdpCollaterals = scdp().collaterals;
            for (uint256 i; i < scdpCollaterals.length; i++) {
                address scdpCollateralAddr = scdpCollaterals[i];
                Asset storage scdpCollateral = cs().assets[scdpCollateralAddr];
                validateLiquidationMarket(asset, cfg, scdpCollateralAddr, scdpCollateral);
                validateLiquidationMarket(scdpCollateralAddr, scdpCollateral, asset, cfg);
            }
        }
    }

    function validateLiquidationMarket(
        address seizedAddr,
        Asset storage seizeAsset,
        address repayKopio,
        Asset storage repayAsset
    ) internal view {
        if (seizeAsset.isGlobalDepositable && repayAsset.isSwapMintable) {
            uint256 seizeReductionPct = (repayAsset.liqIncentiveSCDP.percentMul(seizeAsset.factor));
            uint256 repayIncreasePct = (repayAsset.dFactor.percentMul(scdp().maxLiquidationRatio));
            if (seizeReductionPct >= repayIncreasePct) {
                revert err.SCDP_ASSET_ECONOMY(id(seizedAddr), seizeReductionPct, id(repayKopio), repayIncreasePct);
            }
        }
        if (seizeAsset.isCollateral && repayAsset.isKopio) {
            uint256 seizeReductionPct = (seizeAsset.liqIncentive.percentMul(seizeAsset.factor)) + repayAsset.closeFee;
            uint256 repayIncreasePct = (repayAsset.dFactor.percentMul(ms().maxLiquidationRatio));
            if (seizeReductionPct >= repayIncreasePct) {
                revert err.ICDP_ASSET_ECONOMY(id(seizedAddr), seizeReductionPct, id(repayKopio), repayIncreasePct);
            }
        }
    }

    function validatePushPrice(address asset) internal view {
        Asset storage cfg = cs().assets[asset];
        OraclePrice memory result = pushPrice(cfg.oracles, cfg.ticker);
        if (result.answer <= 0) {
            revert err.INVALID_ORACLE_PRICE(result);
        }
        if (result.isStale) {
            revert err.STALE_PUSH_PRICE(
                id(asset),
                cfg.ticker.toString(),
                int256(result.answer),
                uint8(result.oracle),
                result.feed,
                block.timestamp - result.timestamp,
                result.staleTime
            );
        }
    }
}
