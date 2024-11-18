// solhint-disable no-global-import
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {scdp, sdi} from "scdp/State.sol";
import {TData} from "periphery/data/DataTypes.sol";
import {isSequencerUp} from "common/funcs/Utils.sol";
import {OraclePrice} from "common/Types.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {WadRay} from "vendor/WadRay.sol";
import {ICDPState, ms} from "icdp/State.sol";
import {Arrays} from "libs/Arrays.sol";
import {IAggregatorV3} from "kopio/vendor/IAggregatorV3.sol";
import {IKopio} from "interfaces/IKopio.sol";

import "periphery/data/DataUtils.sol";
import {fromWad, wadUSD} from "common/funcs/Math.sol";
import {Percents} from "common/Constants.sol";

library DataLogic {
    using PercentageMath for *;
    using DataUtils for Asset;
    using DataUtils for ICDPState;
    using WadRay for uint256;
    using Arrays for address[];
    function getAllAssets() internal view returns (address[] memory result) {
        address[] memory mCollaterals = ms().collaterals;
        address[] memory mkopios = ms().kopios;
        address[] memory sAssets = scdp().collaterals;

        address[] memory all = new address[](mCollaterals.length + mkopios.length + sAssets.length);

        uint256 uniques;
        uint256 i;

        for (; i < mCollaterals.length; i++) {
            if (all.findIndex(mCollaterals[i]) == -1) all[uniques++] = mCollaterals[i];
        }

        for (i = 0; i < mkopios.length; i++) {
            if (all.findIndex(mkopios[i]) == -1) all[uniques++] = mkopios[i];
        }

        for (i = 0; i < sAssets.length; i++) {
            if (all.findIndex(sAssets[i]) == -1) all[uniques++] = sAssets[i];
        }

        result = new address[](uniques);

        for (i = 0; i < uniques; i++) result[i] = all[i];
    }

    function getProtocol(PythView calldata prices) internal view returns (TData.Protocol memory result) {
        result.assets = getAssets(prices);
        result.icdp = getICDP();
        result.scdp = getSCDP(prices);
        result.maxDeviation = cs().maxPriceDeviationPct;
        result.oracleDecimals = cs().oracleDecimals;
        result.pythEp = cs().pythEp;
        result.safety = cs().safetyStateSet;
        result.seqGracePeriod = cs().sequencerGracePeriodTime;
        result.seqUp = isSequencerUp(cs().sequencerUptimeFeed, cs().sequencerGracePeriodTime);
        (, , uint256 startedAt, , ) = IAggregatorV3(cs().sequencerUptimeFeed).latestRoundData();
        result.seqStartAt = uint32(startedAt);
        result.time = uint32(block.timestamp);
        result.blockNr = uint32(block.number);
        result.tvl = getTVL(prices);
    }

    function getTVL(PythView calldata prices) internal view returns (uint256 result) {
        address[] memory assets = getAllAssets();
        for (uint256 i; i < assets.length; i++) {
            Asset storage asset = cs().assets[assets[i]];
            result += toWad(IERC20(assets[i]).balanceOf(address(this)), asset.decimals).wadMul(asset.getPrice(prices));
        }
    }

    function getICDP() internal view returns (TData.ICDP memory result) {
        result.LT = ms().liquidationThreshold;
        result.MCR = ms().minCollateralRatio;
        result.MLR = ms().maxLiquidationRatio;
        result.minDebtValue = ms().minDebtValue;
    }

    function getAccount(PythView calldata prices, address _account) internal view returns (TData.Account memory result) {
        result.addr = _account;
        result.bals = getBalances(prices, _account);
        result.icdp = getIAccount(prices, _account);
        result.scdp = getSAccount(prices, _account, getSDepositAssets());
    }

    function getSCDP(PythView calldata prices) internal view returns (TData.SCDP memory result) {
        result.LT = scdp().liquidationThreshold;
        result.MCR = scdp().minCollateralRatio;
        result.MLR = scdp().maxLiquidationRatio;
        result.coverIncentive = uint32(sdi().coverIncentive);
        result.coverThreshold = uint32(sdi().coverThreshold);

        (result.totals, result.deposits) = getSData(prices);
        result.debts = getSDebts(prices);
    }

    function getSDebts(PythView calldata prices) internal view returns (TData.TPos[] memory results) {
        address[] memory kopios = scdp().kopios;
        results = new TData.TPos[](kopios.length);

        for (uint256 i; i < kopios.length; i++) {
            TData.TPosAll memory data = getSAssetData(prices, kopios[i]);
            results[i] = TData.TPos({
                addr: data.addr,
                symbol: data.symbol,
                amount: data.amountDebt,
                amountAdj: data.amountDebt,
                val: data.valDebt,
                valAdj: data.valDebtAdj,
                price: data.price,
                index: -1
            });
        }
    }

    function getSData(
        PythView calldata prices
    ) internal view returns (TData.STotals memory totals, TData.SDeposit[] memory results) {
        address[] memory collaterals = scdp().collaterals;
        results = new TData.SDeposit[](collaterals.length);
        totals.sdiPrice = getSDIPrice(prices);
        totals.valDebt = getEffectiveDebtValue(prices, totals.sdiPrice);

        for (uint256 i; i < collaterals.length; i++) {
            TData.TPosAll memory data = getSAssetData(prices, collaterals[i]);
            totals.valFees += data.valCollFees;
            totals.valColl += data.valColl;
            totals.valCollAdj += data.valCollAdj;
            totals.valDebtAdj += data.valDebtAdj;
            results[i] = TData.SDeposit({
                addr: data.addr,
                liqIndex: scdp().assetIndexes[data.addr].currLiqIndex,
                feeIndex: scdp().assetIndexes[data.addr].currFeeIndex,
                symbol: data.symbol,
                price: data.price,
                amount: data.amountColl,
                amountFees: data.amountCollFees,
                amountSwapDeposit: data.amountSwapDeposit,
                val: data.valColl,
                valAdj: data.valCollAdj,
                valFees: data.valCollFees
            });
        }

        if (totals.valColl == 0) {
            totals.cr = 0;
        } else if (totals.valDebt == 0) {
            totals.cr = type(uint256).max;
        } else {
            totals.cr = totals.valColl.percentDiv(totals.valDebt);
        }
    }

    function getBalances(PythView calldata prices, address _account) internal view returns (TData.Balance[] memory result) {
        address[] memory allAssets = getAllAssets();
        result = new TData.Balance[](allAssets.length);
        for (uint256 i; i < allAssets.length; i++) {
            result[i] = getBalance(prices, _account, allAssets[i]);
        }
    }

    function getAsset(PythView calldata prices, address addr) internal view returns (TData.TAsset memory) {
        Asset storage asset = cs().assets[addr];
        IERC20 token = IERC20(addr);
        OraclePrice memory price = prices.ids.length > 0
            ? pythView(asset.ticker, prices)
            : pushPrice(asset.oracles, asset.ticker);

        IKopio.Wraps memory wrap;
        if (asset.dFactor > 0 && asset.ticker != "ONE") {
            wrap = IKopio(addr).wraps();
        }
        return
            TData.TAsset({
                addr: addr,
                symbol: _symbol(addr),
                wrap: wrap,
                name: token.name(),
                tSupply: token.totalSupply(),
                mSupply: asset.isKopio ? asset.getMintedSupply(addr) : 0,
                price: uint256(price.answer),
                isMarketOpen: asset.isMarketOpen(),
                priceRaw: price,
                config: asset
            });
    }

    function getAssets(PythView calldata prices) internal view returns (TData.TAsset[] memory result) {
        address[] memory assets = getAllAssets();
        result = new TData.TAsset[](assets.length);

        for (uint256 i; i < assets.length; i++) {
            result[i] = getAsset(prices, assets[i]);
        }
    }

    function getBalance(
        PythView calldata prices,
        address _account,
        address _assetAddr
    ) internal view returns (TData.Balance memory result) {
        IERC20 token = IERC20(_assetAddr);
        Asset storage asset = cs().assets[_assetAddr];
        result.addr = _account;
        result.amount = token.balanceOf(_account);
        result.val = asset.exists() ? asset.toCollateralValue(asset.getPrice(prices), result.amount, true) : 0;
        result.token = _assetAddr;
        result.name = token.name();
        result.decimals = token.decimals();
        result.symbol = _symbol(_assetAddr);
    }

    function getSDepositAssets() internal view returns (address[] memory result) {
        address[] memory depositAssets = scdp().collaterals;
        address[] memory assets = new address[](depositAssets.length);

        uint256 length;

        for (uint256 i; i < depositAssets.length; ) {
            if (cs().assets[depositAssets[i]].isGlobalDepositable) {
                assets[length++] = depositAssets[i];
            }
            unchecked {
                i++;
            }
        }

        result = new address[](length);
        for (uint256 i; i < length; i++) result[i] = assets[i];
    }

    function getSAssetData(PythView calldata prices, address _assetAddr) internal view returns (TData.TPosAll memory result) {
        Asset storage asset = cs().assets[_assetAddr];
        result.addr = _assetAddr;
        result.price = asset.getPrice(prices);
        result.symbol = _symbol(_assetAddr);

        if (asset.isSwapMintable) {
            result.amountDebt = asset.toDynamic(scdp().assetData[_assetAddr].debt);
            (result.valDebt, result.valDebtAdj) = asset.toValues(result.price, result.amountDebt, asset.dFactor);
            result.amountSwapDeposit = scdp().swapDepositAmount(_assetAddr, asset);
        }

        if (asset.isGlobalCollateral) {
            result.amountColl = scdp().totalDepositAmount(_assetAddr, asset);
            (result.valColl, result.valCollAdj) = asset.toValues(result.price, result.amountColl, asset.factor);

            uint256 feeIndex = scdp().assetIndexes[_assetAddr].currFeeIndex;
            if (feeIndex != 0) {
                result.amountCollFees = result.amountColl.wadToRay().rayMul(feeIndex).rayToWad();
                result.valCollFees = result.valColl.wadToRay().rayMul(feeIndex).rayToWad();
            }
        }
    }

    function getIAssetData(
        PythView calldata prices,
        address _account,
        address _assetAddr
    ) internal view returns (TData.TPosAll memory result) {
        Asset storage asset = cs().assets[_assetAddr];
        result.addr = _assetAddr;
        result.symbol = _symbol(_assetAddr);
        result.price = asset.getPrice(prices);

        if (asset.isKopio) {
            result.amountDebt = ms().accountDebtAmount(_account, _assetAddr, asset);
            (result.valDebt, result.valDebtAdj) = asset.toValues(result.price, result.amountDebt, asset.dFactor);
        }

        if (asset.isCollateral) {
            result.amountColl = ms().accountCollateralAmount(_account, _assetAddr, asset);
            (result.valColl, result.valCollAdj) = asset.toValues(result.price, result.amountColl, asset.factor);
        }
    }

    function getIAccount(PythView calldata prices, address _account) internal view returns (TData.IAccount memory result) {
        (result.totals.valColl, result.deposits) = getIDeposits(prices, _account);
        (result.totals.valDebt, result.debts) = getIDebts(prices, _account);
        if (result.totals.valColl == 0) {
            result.totals.cr = 0;
        } else if (result.totals.valDebt == 0) {
            result.totals.cr = type(uint256).max;
        } else {
            result.totals.cr = result.totals.valColl.percentDiv(result.totals.valDebt);
        }
    }

    function getIDeposits(
        PythView calldata prices,
        address _account
    ) internal view returns (uint256 totalValue, TData.TPos[] memory result) {
        address[] memory colls = ms().collaterals;
        result = new TData.TPos[](colls.length);

        for (uint256 i; i < colls.length; i++) {
            address addr = colls[i];
            TData.TPosAll memory data = getIAssetData(prices, _account, addr);
            Arrays.FindResult memory findResult = ms().collateralsOf[_account].find(addr);
            totalValue += data.valCollAdj;
            result[i] = TData.TPos({
                addr: addr,
                symbol: _symbol(addr),
                amount: data.amountColl,
                amountAdj: 0,
                val: data.valColl,
                valAdj: data.valCollAdj,
                price: data.price,
                index: findResult.exists ? int256(findResult.index) : -1
            });
        }
    }

    function getIDebts(
        PythView calldata prices,
        address _account
    ) internal view returns (uint256 totalValue, TData.TPos[] memory result) {
        address[] memory kopios = ms().kopios;
        result = new TData.TPos[](kopios.length);

        for (uint256 i; i < kopios.length; i++) {
            address addr = kopios[i];
            TData.TPosAll memory data = getIAssetData(prices, _account, addr);
            Arrays.FindResult memory findResult = ms().mints[_account].find(addr);
            totalValue += data.valDebtAdj;
            result[i] = TData.TPos({
                addr: addr,
                symbol: _symbol(addr),
                amount: data.amountDebt,
                amountAdj: 0,
                val: data.valDebt,
                valAdj: data.valDebtAdj,
                price: data.price,
                index: findResult.exists ? int256(findResult.index) : -1
            });
        }
    }

    function getSAccount(
        PythView calldata prices,
        address _account,
        address[] memory _assets
    ) internal view returns (TData.SAccount memory result) {
        result.addr = _account;
        (result.totals.valColl, result.totals.valFees, result.deposits) = getSAccountTotals(prices, _account, _assets);
    }

    function getSAccountTotals(
        PythView calldata prices,
        address _account,
        address[] memory _assets
    ) internal view returns (uint256 totalVal, uint256 totalValFees, TData.SDepositUser[] memory datas) {
        address[] memory assets = scdp().collaterals;
        datas = new TData.SDepositUser[](_assets.length);

        for (uint256 i; i < assets.length; ) {
            address asset = assets[i];
            TData.SDepositUser memory assetData = getSAccountDeposit(prices, _account, asset);

            totalVal += assetData.val;
            totalValFees += assetData.valFees;

            for (uint256 j; j < _assets.length; ) {
                if (asset == _assets[j]) {
                    datas[j] = assetData;
                }
                unchecked {
                    j++;
                }
            }

            unchecked {
                i++;
            }
        }
    }

    function getSAccountDeposit(
        PythView calldata prices,
        address _account,
        address _assetAddr
    ) internal view returns (TData.SDepositUser memory result) {
        Asset storage asset = cs().assets[_assetAddr];

        result.price = asset.getPrice(prices);

        result.amount = scdp().accountDeposits(_account, _assetAddr, asset);
        result.amountFees = scdp().accountFees(_account, _assetAddr, asset);
        result.val = asset.toCollateralValue(result.price, result.amount, true);
        result.valFees = asset.toCollateralValue(result.price, result.amountFees, true);

        result.symbol = _symbol(_assetAddr);
        result.addr = _assetAddr;
        result.liqIndexAccount = scdp().accountIndexes[_account][_assetAddr].lastLiqIndex;
        result.feeIndexAccount = scdp().accountIndexes[_account][_assetAddr].lastFeeIndex;
        result.accIndexTime = scdp().accountIndexes[_account][_assetAddr].timestamp;
        result.liqIndexCurrent = scdp().assetIndexes[_assetAddr].currLiqIndex;
        result.feeIndexCurrent = scdp().assetIndexes[_assetAddr].currFeeIndex;
    }

    function _symbol(address addr) internal view returns (string memory) {
        return addr == 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8 ? "USDC.e" : IERC20(addr).symbol();
    }

    /// @notice Returns the total effective debt value of the SCDP.
    /// @notice Calculation is done in wad precision but returned as oracle precision.
    function getEffectiveDebtValue(PythView calldata prices, uint256 sdiPrice) internal view returns (uint256 result) {
        uint256 coverValue = getTotalCoverValue(prices);
        uint256 coverAmount = coverValue != 0 ? coverValue.wadDiv(sdiPrice) : 0;
        uint256 totalDebt = sdi().totalDebt;

        if (coverAmount >= totalDebt) return 0;

        if (coverValue == 0) {
            result = totalDebt;
        } else {
            result = (totalDebt - coverAmount);
        }

        return fromWad(result.wadMul(sdiPrice), cs().oracleDecimals);
    }

    /// @notice Get the price of SDI in USD (WAD precision, so 18 decimals).
    function getSDIPrice(PythView calldata prices) internal view returns (uint256) {
        uint256 totalValue = getTotalDebtValueAtRatioSCDP(prices, Percents.HUNDRED, false);
        if (totalValue == 0) {
            return 1e18;
        }
        return toWad(totalValue, cs().oracleDecimals).wadDiv(sdi().totalDebt);
    }

    /**
     * @notice Returns the value of the kopio held in the pool at a ratio.
     * @param ratio Percentage ratio to apply for the value in 1e4 percentage precision (uint32).
     * @param noFactors Whether to ignore dFactor
     * @return totalValue Total value in USD
     */
    function getTotalDebtValueAtRatioSCDP(
        PythView calldata prices,
        uint32 ratio,
        bool noFactors
    ) internal view returns (uint256 totalValue) {
        address[] memory assets = scdp().kopios;
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            uint256 debtAmount = asset.toDynamic(scdp().assetData[assets[i]].debt);
            unchecked {
                if (debtAmount != 0) {
                    totalValue += asset.toDebtValue(debtAmount, asset.getPrice(prices), noFactors);
                }
                i++;
            }
        }

        // Multiply if needed
        if (ratio != Percents.HUNDRED) {
            totalValue = totalValue.percentMul(ratio);
        }
    }

    function getTotalCoverValue(PythView calldata prices) internal view returns (uint256 result) {
        address[] memory assets = sdi().coverAssets;
        for (uint256 i; i < assets.length; ) {
            unchecked {
                result += getCoverAssetValue(prices, assets[i]);
                i++;
            }
        }
    }

    /// @notice Get total deposit value of `asset` in USD, wad precision.
    function getCoverAssetValue(PythView calldata prices, address addr) internal view returns (uint256) {
        Asset storage asset = cs().assets[addr];
        if (!asset.isCoverAsset) return 0;

        uint256 bal = IERC20(addr).balanceOf(sdi().coverRecipient);
        if (bal == 0) return 0;

        return wadUSD(bal, asset.decimals, asset.getPrice(prices), cs().oracleDecimals);
    }
}
