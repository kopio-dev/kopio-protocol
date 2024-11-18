// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {IKopioShare} from "interfaces/IKopioShare.sol";
import {IONE} from "interfaces/IONE.sol";
import {IMarketStatus} from "interfaces/IMarketStatus.sol";

import {WadRay} from "vendor/WadRay.sol";
import {id, err} from "common/Errors.sol";
import {Constants, Enums} from "common/Constants.sol";
import {Asset, Oracle} from "common/Types.sol";
import {toWad} from "common/funcs/Math.sol";
import {safePrice, SDIPrice} from "common/funcs/Price.sol";
import {cs} from "common/State.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {ms} from "icdp/State.sol";
import {scdp} from "scdp/State.sol";
import {IERC20} from "kopio/token/IERC20.sol";

library Assets {
    using WadRay for uint256;
    using PercentageMath for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                Asset Prices                                */
    /* -------------------------------------------------------------------------- */

    function price(Asset storage self) internal view returns (uint256) {
        return price(self, cs().maxPriceDeviationPct);
    }

    function price(Asset storage self, uint256 maxDeviationPct) internal view returns (uint256) {
        return safePrice(self.ticker, self.oracles, maxDeviationPct);
    }

    /**
     * @notice Get value for @param amount of @param self in uint256, assuming asset has 18 decimals.
     */
    function kopioUSD(Asset storage self, uint256 amount) internal view returns (uint256) {
        return self.price().wadMul(amount);
    }

    /**
     * @notice Get value for @param amount of @param self in uint256, converting decimals to 18.
     */
    function assetUSD(Asset storage self, uint256 amount) internal view returns (uint256) {
        return self.toCollateralValue(amount, true);
    }

    function isMarketOpen(Asset storage self) internal view returns (bool) {
        return IMarketStatus(cs().marketStatusProvider).getTickerStatus(self.ticker);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Conversions                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Ensure repayment value (and amount), clamp to max if necessary.
     * @param maxRepayValue The max liquidatable USD (uint256).
     * @param repayAmount The repay amount (uint256).
     * @return uint256 Effective repayment value.
     * @return uint256 Effective repayment amount.
     */
    function boundRepayValue(
        Asset storage self,
        uint256 maxRepayValue,
        uint256 repayAmount
    ) internal view returns (uint256, uint256) {
        uint256 assetPrice = self.price();
        uint256 repayValue = repayAmount.wadMul(assetPrice);

        if (repayValue > maxRepayValue) {
            repayAmount = maxRepayValue.wadDiv(assetPrice);
            repayValue = maxRepayValue;
        }

        return (repayValue, repayAmount);
    }

    /**
     * @notice Gets the value + factored value of `amount` with price.
     * @param amount Amount of asset
     * @param factor Factor to apply to the value.
     * @return value Value.
     * @return valueAdj Factored value.
     * @return price_ Price of the asset.
     */
    function toValues(
        Asset storage self,
        uint256 amount,
        uint256 factor
    ) internal view returns (uint256 value, uint256 valueAdj, uint256 price_) {
        price_ = self.price();
        if (amount == 0) return (0, 0, price_);

        value = toWad(amount, self.decimals).wadMul(price_);
        valueAdj = factor != 0 ? value.percentMul(factor) : value;
    }

    function toCollateralValue(Asset storage self, uint256 amount, bool noFactors) internal view returns (uint256 value) {
        (, value, ) = self.toValues(amount, noFactors ? 0 : self.factor);
    }

    /**
     * @notice Gets the USD value for asset and amount.
     * @param amount Amount of the asset to calculate the value for.
     * @param noFactors Value ignores factors.
     * @return value The value of the amount
     */
    function toDebtValue(Asset storage self, uint256 amount, bool noFactors) internal view returns (uint256 value) {
        if (amount == 0) return 0;
        value = self.kopioUSD(amount);

        if (!noFactors) {
            value = value.percentMul(self.dFactor);
        }
    }

    /**
     * @notice Get amount from a value.
     * @param value value to use
     * @param noFactors whether to use factors or not.
     * @return amount amount for the provided value.
     */
    function toDebtAmount(Asset storage self, uint256 value, bool noFactors) internal view returns (uint256 amount) {
        if (value == 0) return 0;

        uint256 price_ = self.price();
        if (!noFactors) {
            price_ = price_.percentMul(self.dFactor);
        }

        return value.wadDiv(price_);
    }

    /// @notice Converts amount of assets to SDI.
    function debtToSDI(Asset storage asset, uint256 amount, bool noFactors) internal view returns (uint256 shares) {
        return toWad(asset.toDebtValue(amount, noFactors), cs().oracleDecimals).wadDiv(SDIPrice());
    }

    /**
     * @notice Keep debt over the minimum debt value.
     * @param self asset being burned.
     * @param burned mmount burned.
     * @param debt amount before burn.
     * @return amount >= minDebtAmount
     */
    function checkDust(Asset storage self, uint256 burned, uint256 debt) internal view returns (uint256 amount) {
        if (burned == debt) return burned;
        // If the requested burn would put the user's debt position below the minimum
        // debt value, close up to the minimum debt value instead.
        uint256 value = self.toDebtValue(debt - burned, true);
        uint256 minDebtValue = ms().minDebtValue;
        if (value > 0 && value < minDebtValue) {
            amount = debt - minDebtValue.wadDiv(self.price());
        } else {
            amount = burned;
        }
    }

    /**
     * @notice Check min debt value against an amount.
     * @param self asset configuration
     * @param asset kopio address.
     * @param debt the debt amount
     */
    function ensureMinDebtValue(Asset storage self, address asset, uint256 debt) internal view {
        uint256 value = self.kopioUSD(debt);
        uint256 minDebtValue = ms().minDebtValue;
        if (value < minDebtValue) revert err.MINT_VALUE_LESS_THAN_MIN_DEBT_VALUE(id(asset), value, minDebtValue);
    }

    /**
     * @notice EDGE CASE: If collateral is also a kopio, ensure deposit amount is above 1e12.
     * @dev this is due to rebases.
     */
    function ensureMinCollateralAmount(Asset storage self, address addr, uint256 amount) internal view {
        if (amount > Constants.MIN_COLLATERAL || amount == 0 || self.share == address(0)) return;

        revert err.COLLATERAL_AMOUNT_LOW(id(addr), amount, Constants.MIN_COLLATERAL);
    }

    /**
     * @notice Get the minimum value required to back debt at a given CR.
     * @param amount the debt amount.
     * @param ratio ratio to apply for the minimum collateral value.
     * @return minCollateral the minimum collateral required for `amount`t.
     */
    function minCollateralValueAtRatio(
        Asset storage self,
        uint256 amount,
        uint32 ratio
    ) internal view returns (uint256 minCollateral) {
        if (amount == 0) return 0;
        // Calculate the collateral value required to back this asset amount at the given ratio
        return self.toDebtValue(amount, false).percentMul(ratio);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Utils                                   */
    /* -------------------------------------------------------------------------- */
    function exists(Asset storage self) internal view returns (bool) {
        return self.ticker != 0;
    }

    /**
     * @notice Oracle configuration at the specified index.
     * @param at Position.
     * @return oracle Oracle identifier.
     * @return cfg Oracle configuration.
     */
    function oracleAt(Asset storage self, uint8 at) internal view returns (Enums.OracleType oracle, Oracle storage cfg) {
        oracle = self.oracles[at];
        cfg = cs().oracles[self.ticker][oracle];
    }

    /**
     * @notice Amount of shares -> amount of assets
     * @dev DO use this function when reading values storage.
     * @dev DONT use this function when writing to storage.
     * @param shares Unrebased amount to convert.
     * @return uint256 Possibly rebased amount of asset
     */
    function toDynamic(Asset storage self, uint256 shares) internal view returns (uint256) {
        if (shares == 0) return 0;
        if (self.share != address(0)) {
            return IKopioShare(self.share).convertToAssets(shares);
        }
        return shares;
    }

    /**
     * @notice Amount of assets -> amount of shares
     * @dev DONT use this function when reading from storage.
     * @dev DO use this function when writing to storage.
     * @param self asset.
     * @param assets amount of assets.
     * @return uint256 amount of shares
     */
    function toStatic(Asset storage self, uint256 assets) internal view returns (uint256) {
        if (assets == 0) return 0;
        if (self.share != address(0)) {
            return IKopioShare(self.share).convertToShares(assets);
        }
        return assets;
    }

    /**
     * @notice Validate debt limit is not exceeded.
     * @param self asset
     * @param addr Address of the asset minted.
     * @param amount Amount minted.
     * @dev Reverts debt limit is exceeded.
     */
    function ensureMintLimitICDP(Asset storage self, address addr, uint256 amount) internal view {
        uint256 newSupply = getMintedSupply(self, addr) + amount;
        if (newSupply > self.mintLimit) {
            revert err.EXCEEDS_ASSET_MINTING_LIMIT(id(addr), newSupply, self.mintLimit);
        }
    }

    /**
     * @notice Get the icdp supply of a given asset
     * @param self asset
     * @param addr Address of the asset being minted.
     * @return uint256 the minted supply
     */
    function getMintedSupply(Asset storage self, address addr) internal view returns (uint256) {
        if (self.share == addr) {
            return _getONESupply(addr);
        }
        return _getSupply(addr, self.share);
    }

    function _getSupply(address asset, address _share) private view returns (uint256) {
        IKopioShare share = IKopioShare(_share);
        uint256 supply = share.totalSupply() - share.balanceOf(asset) - scdp().assetData[asset].debt;
        if (supply == 0) return 0;
        return share.convertToAssets(supply);
    }

    function _getONESupply(address asset) private view returns (uint256) {
        return IERC20(asset).totalSupply() - (IERC20(IONE(asset).vault()).balanceOf(asset) + scdp().assetData[asset].debt);
    }
}
