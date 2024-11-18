import { expect } from '@test/chai'
import { type DefaultFixture, defaultFixture } from '@utils/test/fixtures'

import type { KopioConfig } from '@/types'
import type { AssetStruct } from '@/types/typechain/src/contracts/interfaces/KopioCore'
import { addMockKopio } from '@utils/test/helpers/assets'
import { addMockExtAsset } from '@utils/test/helpers/collaterals'
import { getAssetConfig } from '@utils/test/helpers/general'
import { createOracles } from '@utils/test/helpers/oracle'
import { testCollateralConfig, testICDPParams, testKopioConfig } from '@utils/test/mocks'
import { fromBig, toBig } from '@utils/values'

describe('ICDP - Configuration', function () {
  let f: DefaultFixture
  this.slow(1000)

  this.beforeEach(async function () {
    f = await defaultFixture()
  })

  describe('#configuration', () => {
    it('can modify all parameters', async function () {
      const update = testICDPParams(hre.users.treasury.address)
      await expect(hre.Diamond.setMCR(update.minCollateralRatio)).to.not.be.reverted
      await expect(hre.Diamond.setLT(update.liquidationThreshold)).to.not.be.reverted
      await expect(hre.Diamond.setMLR(update.maxLiquidationRatio)).to.not.be.reverted

      const params = await hre.Diamond.getICDPParams()

      expect(update.minCollateralRatio).eq(params.minCollateralRatio)
      expect(update.maxLiquidationRatio).eq(params.maxLiquidationRatio)
      expect(update.liquidationThreshold).eq(params.liquidationThreshold)
    })

    it('can add a collateral asset', async function () {
      const { contract } = await addMockExtAsset(testCollateralConfig)
      expect(await hre.Diamond.getCollateralExists(contract.address)).eq(true)
      const priceOfOne = await hre.Diamond.getValue(contract.address, toBig(1))
      expect(Number(priceOfOne)).eq(toBig(testCollateralConfig.price!, 8))
    })

    it('can add a asset', async function () {
      const { contract, assetInfo } = await addMockKopio({
        ...testKopioConfig,
        name: 'Kopio 5',
        symbol: 'Kopio5',
        ticker: 'Kopio5',
      })

      const values = await assetInfo()
      const priceAnswer = fromBig(await hre.Diamond.getValue(contract.address, toBig(1)), 8)
      const config = testKopioConfig.kopioConfig!

      expect(values.isKopio).eq(true)
      expect(values.dFactor).eq(config.dFactor)
      expect(priceAnswer).eq(testKopioConfig.price)
      expect(values.mintLimit).eq(config.mintLimit)
      expect(values.closeFee).eq(config.closeFee)
      expect(values.openFee).eq(config.openFee)
    })

    it('can update oracle decimals', async function () {
      const decimals = 8
      await hre.Diamond.setOracleDecimals(decimals)
      expect(await hre.Diamond.getOracleDecimals()).eq(decimals)
    })

    it('can update icdp MLR', async function () {
      const currentMLM = await hre.Diamond.getMLR()
      const newMLR = 1.42e4

      expect(currentMLM).not.eq(newMLR)

      await expect(hre.Diamond.setMLR(newMLR)).to.not.be.reverted
      expect(await hre.Diamond.getMLR()).eq(newMLR)
    })

    it('can update oracle deviation', async function () {
      const currentDeviationPct = await hre.Diamond.getOracleDeviationPct()
      const newDeviationPct = 0.03e4

      expect(currentDeviationPct).not.eq(newDeviationPct)

      await expect(hre.Diamond.setOracleDeviation(newDeviationPct)).to.not.be.reverted
      expect(await hre.Diamond.getOracleDeviationPct()).eq(newDeviationPct)
    })

    it('can update dFactor of an asset', async function () {
      const oldRatio = (await hre.Diamond.getAsset(f.Kopio.address)).dFactor
      const newRatio = 1.2e4

      expect(oldRatio === newRatio).to.be.false

      await expect(hre.Diamond.setDFactor(f.Kopio.address, newRatio)).to.not.be.reverted
      expect((await hre.Diamond.getAsset(f.Kopio.address)).dFactor === newRatio).to.be.true
    })
    it('can update cFactor of collateral', async function () {
      const oldRatio = (await hre.Diamond.getAsset(f.Collateral.address)).factor
      const newRatio = 0.9e4
      expect(oldRatio === newRatio).to.be.false
      await expect(hre.Diamond.setCFactor(f.Collateral.address, newRatio)).to.not.be.reverted
      expect((await hre.Diamond.getAsset(f.Collateral.address)).factor === newRatio).to.be.true
    })

    it('can update configuration of an asset', async function () {
      const oracleAnswer = fromBig((await f.Kopio.priceFeed.latestRoundData())[1], 8)
      const priceOfOne = fromBig(await hre.Diamond.getValue(f.Kopio.address, toBig(1)), 8)

      expect(oracleAnswer).eq(priceOfOne)
      expect(oracleAnswer).eq(testKopioConfig.price)

      const update: KopioConfig = {
        dFactor: 1.2e4,
        mintLimit: toBig(12000),
        closeFee: 0.03e4,
        openFee: 0.03e4,
        share: f.Kopio.share.address,
      }
      const FakeFeed = await createOracles(hre, f.Kopio.pythId.toString(), 20)
      const newConfig = await getAssetConfig(f.Kopio.contract, {
        ...testKopioConfig,
        feed: FakeFeed.address,
        price: 20,
        kopioConfig: update,
      })

      await hre.Diamond.setFeedsForTicker(newConfig.assetStruct.ticker, newConfig.feedConfig)
      await hre.Diamond.connect(hre.users.deployer).updateAsset(f.Kopio.address, newConfig.assetStruct)

      const newValues = await hre.Diamond.getAsset(f.Kopio.address)
      const updatedOracleAnswer = fromBig((await FakeFeed.latestRoundData())[1], 8)
      const newPriceOfOne = fromBig(await hre.Diamond.getValue(f.Kopio.address, toBig(1)), 8)

      expect(newValues.isKopio).eq(true)
      expect(newValues.isCollateral).eq(false)
      expect(newValues.dFactor).eq(update.dFactor)
      expect(newValues.mintLimit).eq(update.mintLimit)

      expect(updatedOracleAnswer).eq(newPriceOfOne)
      expect(updatedOracleAnswer).eq(20)

      const update2: AssetStruct = {
        ...(await hre.Diamond.getAsset(f.Kopio.address)),
        dFactor: 1.75e4,
        mintLimit: toBig(12000),
        closeFee: 0.052e4,
        openFee: 0.052e4,
        isSwapMintable: true,
        swapInFee: 0.052e4,
        liqIncentiveSCDP: 1.1e4,
        share: f.Kopio.share.address,
      }

      await hre.Diamond.updateAsset(f.Kopio.address, update2)

      const newValues2 = await hre.Diamond.getAsset(f.Kopio.address)
      expect(newValues2.isKopio).eq(true)
      expect(newValues2.isGlobalCollateral).eq(true)
      expect(newValues2.isSwapMintable).eq(true)
      expect(newValues2.isCollateral).eq(false)
      expect(newValues2.isGlobalDepositable).eq(false)
      expect(newValues2.isCoverAsset).eq(false)
      expect(newValues2.dFactor).eq(update2.dFactor)
      expect(newValues2.openFee).eq(update2.closeFee)
      expect(newValues2.closeFee).eq(update2.openFee)
      expect(newValues2.swapInFee).eq(update2.swapInFee)
      expect(newValues2.mintLimit).eq(update2.mintLimit)

      await f.Kopio.setPrice(10)
    })
  })
})
