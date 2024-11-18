import type {
  AssetStruct,
  KopioCore,
  SCDPLiquidationOccuredEvent,
  SwapEvent,
} from '@/types/typechain/src/contracts/interfaces/KopioCore'
import { getSCDPInitializer } from '@config/hardhat/deploy'
import { Errors } from '@utils/errors'
import { getNamedEvent } from '@utils/events'
import { type SCDPFixture, scdpFixture } from '@utils/test/fixtures'
import { mintKopio } from '@utils/test/helpers/assets'
import { depositCollateral } from '@utils/test/helpers/collaterals'
import { RAY, toBig } from '@utils/values'
import { expect } from 'chai'
import { maxUint256 } from 'viem'

const depositAmount = 1000
const depositValue = depositAmount.ebn(8)
const initialDepositValue = depositAmount.ebn(8)
const depositAmount18Dec = depositAmount.ebn()
const depositAmount8Dec = depositAmount.ebn(8)

describe('SCDP', async function () {
  let f: SCDPFixture
  this.slow(5000)

  beforeEach(async function () {
    f = await scdpFixture()
    await f.reset()
  })

  describe('#Configuration', async () => {
    it('should be initialized correctly', async () => {
      const { args } = await getSCDPInitializer(hre)

      const configuration = await hre.Diamond.getGlobalParameters()
      expect(configuration.liquidationThreshold).eq(args.liquidationThreshold)
      expect(configuration.minCollateralRatio).eq(args.minCollateralRatio)
      expect(configuration.maxLiquidationRatio).eq(Number(args.liquidationThreshold) + 0.01e4)

      const collaterals = await hre.Diamond.getCollateralsSCDP()
      expect(collaterals).to.include.members([
        f.Collateral.address,
        f.Collateral8Dec.address,
        f.Kopio.address,
        f.Kopio2.address,
        f.ONE.address,
      ])
      const kopios = await hre.Diamond.getKopiosSCDP()
      expect(kopios).to.include.members([f.Kopio.address, f.Kopio2.address, f.ONE.address])

      const depositsEnabled = await Promise.all([
        hre.Diamond.getGlobalDepositEnabled(f.Collateral.address),
        hre.Diamond.getGlobalDepositEnabled(f.Collateral8Dec.address),
        hre.Diamond.getGlobalDepositEnabled(f.Kopio.address),
        hre.Diamond.getGlobalDepositEnabled(f.Kopio2.address),
        hre.Diamond.getGlobalDepositEnabled(f.ONE.address),
      ])

      expect(depositsEnabled).to.deep.eq([true, true, false, false, true])

      const depositAssets = await hre.Diamond.getAssetAddresses(3)

      expect(depositAssets).to.include.members([f.Collateral.address, f.Collateral8Dec.address, f.ONE.address])
    })
    it('should be able to whitelist new deposit asset', async () => {
      const assetInfoBefore = await hre.Diamond.getAsset(f.Kopio2.address)
      expect(assetInfoBefore.isGlobalDepositable).eq(false)
      await hre.Diamond.updateAsset(f.Kopio2.address, {
        ...assetInfoBefore,
        isGlobalDepositable: true,
        depositLimitSCDP: 1,
      })
      const assetInfoAfter = await hre.Diamond.getAsset(f.Kopio2.address)
      expect(assetInfoAfter.decimals).eq(await f.Kopio2.contract.decimals())

      expect(assetInfoAfter.depositLimitSCDP).eq(1)

      const indicesAfter = await hre.Diamond.getAssetIndexesSCDP(f.Kopio2.address)
      expect(indicesAfter.currLiqIndex).eq(RAY)
      expect(indicesAfter.currFeeIndex).eq(RAY)

      expect(await hre.Diamond.getGlobalDepositEnabled(f.Kopio2.address)).eq(true)
    })

    it('should be able to update deposit limit of asset', async () => {
      await hre.Diamond.setGlobalDepositLimit(f.Collateral.address, 1)
      const collateral = await hre.Diamond.getAsset(f.Collateral.address)
      expect(collateral.decimals).eq(await f.Collateral.contract.decimals())
      expect(collateral.depositLimitSCDP).eq(1)

      const indicesAfter = await hre.Diamond.getAssetIndexesSCDP(f.Collateral.address)
      expect(indicesAfter.currLiqIndex).eq(RAY)
      expect(indicesAfter.currFeeIndex).eq(RAY)
    })

    it('should be able to disable a deposit asset', async () => {
      await hre.Diamond.setGlobalDepositEnabled(f.Collateral.address, false)
      const collaterals = await hre.Diamond.getCollateralsSCDP()
      expect(collaterals).to.include(f.Collateral.address)
      const depositAssets = await hre.Diamond.getAssetAddresses(3)
      expect(depositAssets).to.not.include(f.Collateral.address)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Collateral.address)).eq(false)
    })

    it('should be able to disable and enable a collateral asset', async () => {
      await hre.Diamond.setGlobalCollateralEnabled(f.Collateral.address, false)

      expect(await hre.Diamond.getCollateralsSCDP()).to.not.include(f.Collateral.address)
      expect(await hre.Diamond.getAssetAddresses(3)).to.not.include(f.Collateral.address)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Collateral.address)).eq(true)

      await hre.Diamond.setGlobalDepositEnabled(f.Collateral.address, false)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Collateral.address)).eq(false)

      await hre.Diamond.setGlobalCollateralEnabled(f.Collateral.address, true)
      expect(await hre.Diamond.getCollateralsSCDP()).to.include(f.Collateral.address)
      expect(await hre.Diamond.getAssetAddresses(3)).to.not.include(f.Collateral.address)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Collateral.address)).eq(false)

      await hre.Diamond.setGlobalDepositEnabled(f.Collateral.address, true)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Collateral.address)).eq(true)
      expect(await hre.Diamond.getAssetAddresses(3)).to.include(f.Collateral.address)
    })

    it('should be able to add whitelisted asset', async () => {
      const assetInfo = await hre.Diamond.getAsset(f.Kopio.address)
      expect(assetInfo.swapInFee).eq(f.swapKopioConfig.swapInFee)
      expect(assetInfo.swapOutFee).eq(f.swapKopioConfig.swapOutFee)
      expect(assetInfo.liqIncentiveSCDP).eq(f.swapKopioConfig.liqIncentiveSCDP)
      expect(assetInfo.protocolFeeShareSCDP).eq(f.swapKopioConfig.protocolFeeShareSCDP)
    })

    it('should be able to update a whitelisted asset', async () => {
      const update: AssetStruct = {
        ...f.Kopio.config.assetStruct,
        swapInFee: 0.05e4,
        swapOutFee: 0.05e4,
        liqIncentiveSCDP: 1.06e4,
        protocolFeeShareSCDP: 0.4e4,
      }

      await hre.Diamond.updateAsset(f.Kopio.address, update)
      const assetInfo = await hre.Diamond.getAsset(f.Kopio.address)
      expect(assetInfo.swapInFee).eq(update.swapInFee)
      expect(assetInfo.swapOutFee).eq(update.swapOutFee)
      expect(assetInfo.protocolFeeShareSCDP).eq(update.protocolFeeShareSCDP)
      expect(assetInfo.liqIncentiveSCDP).eq(update.liqIncentiveSCDP)

      const kopios = await hre.Diamond.getKopiosSCDP()
      expect(kopios).to.include(f.Kopio.address)
      const collaterals = await hre.Diamond.getCollateralsSCDP()
      expect(collaterals).to.include(f.Kopio.address)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Kopio.address)).eq(false)
    })

    it('should be able to remove a whitelisted asset', async () => {
      await hre.Diamond.setSwapEnabled(f.Kopio.address, false)
      const kopios = await hre.Diamond.getKopiosSCDP()
      expect(kopios).to.not.include(f.Kopio.address)
      expect(await hre.Diamond.getGlobalDepositEnabled(f.Kopio.address)).eq(false)
    })

    it('should be able to enable and disable swap pairs', async () => {
      await hre.Diamond.setSwapRoutes([
        {
          assetIn: f.Collateral.address,
          assetOut: f.Kopio.address,
          enabled: true,
        },
      ])
      expect(await hre.Diamond.getRouteEnabled(f.Collateral.address, f.Kopio.address)).eq(true)
      expect(await hre.Diamond.getRouteEnabled(f.Kopio.address, f.Collateral.address)).eq(true)

      await hre.Diamond.setSwapRoutes([
        {
          assetIn: f.Collateral.address,
          assetOut: f.Kopio.address,
          enabled: false,
        },
      ])
      expect(await hre.Diamond.getRouteEnabled(f.Collateral.address, f.Kopio.address)).eq(false)
      expect(await hre.Diamond.getRouteEnabled(f.Kopio.address, f.Collateral.address)).eq(false)
    })
  })

  describe('#Deposit', async function () {
    it('should be able to deposit collateral, calculate correct deposit values', async function () {
      const expectedValueUnadjusted = toBig(f.CollateralPrice.num(8) * depositAmount, 8)
      const expectedValueAdjusted = (f.CollateralPrice.num(8) * depositAmount).ebn(8) // cfactor = 1

      await hre.Diamond.setGlobalIncome(f.Collateral.address)

      await Promise.all(
        f.usersArr.map(user => {
          return hre.Diamond.connect(user).depositSCDP(user.address, f.Collateral.address, depositAmount18Dec)
        }),
      )

      const prices = hre.viewData()

      const [userInfos, { scdp }, [assetInfo]] = await Promise.all([
        hre.Diamond.sDataAccounts(
          prices,
          f.usersArr.map(user => user.address),
          [f.Collateral.address],
        ),
        hre.Diamond.aDataProtocol(prices),
        hre.Diamond.sDataAssets(prices, [f.Collateral.address]),
      ])

      for (const userInfo of userInfos) {
        const balance = await f.Collateral.balanceOf(userInfo.addr)

        expect(balance).eq(0)
        expect(userInfo.deposits[0].amountFees).eq(0)
        expect(userInfo.deposits[0].amount).eq(depositAmount18Dec)
        expect(userInfo.totals.valColl).eq(expectedValueUnadjusted)
        expect(userInfo.totals.valFees).eq(0)
        expect(userInfo.deposits[0].val).eq(expectedValueUnadjusted)
        expect(userInfo.deposits[0].valFees).eq(0)
      }

      expect(await f.Collateral.balanceOf(hre.Diamond.address)).eq(depositAmount18Dec.mul(f.usersArr.length))
      expect(assetInfo.amountColl).eq(depositAmount18Dec.mul(f.usersArr.length))
      expect(assetInfo.valColl).eq(expectedValueUnadjusted.mul(f.usersArr.length))
      expect(scdp.totals.valColl).eq(expectedValueUnadjusted.mul(f.usersArr.length))
      expect(scdp.totals.valDebt).eq(0)

      // Adjusted
      expect(assetInfo.valCollAdj).eq(expectedValueAdjusted.mul(f.usersArr.length))
      expect(scdp.totals.valCollAdj).eq(expectedValueUnadjusted.mul(f.usersArr.length))

      expect(scdp.totals.valDebt).eq(0)
      expect(scdp.totals.cr).eq(maxUint256)
    })

    it('should be able to deposit multiple collaterals, calculate correct deposit values', async function () {
      const expectedValueUnadjusted = toBig(f.CollateralPrice.num(8) * depositAmount, 8)
      const expectedValueAdjusted = toBig((f.CollateralPrice.num(8) / 1) * depositAmount, 8) // cfactor = 1

      const expectedValueUnadjusted8Dec = toBig(f.CollateralPrice.num(8) * depositAmount, 8)
      const expectedValueAdjusted8Dec = toBig(f.CollateralPrice.num(8) * 0.8 * depositAmount, 8) // cfactor = 0.8

      await Promise.all(
        f.usersArr.map(async user => {
          const User = hre.Diamond.connect(user)
          await hre.Diamond.setGlobalIncome(f.Collateral.address)
          await User.depositSCDP(user.address, f.Collateral.address, depositAmount18Dec)
          await hre.Diamond.setGlobalIncome(f.Collateral8Dec.address)
          await User.depositSCDP(user.address, f.Collateral8Dec.address, depositAmount8Dec)
        }),
      )
      const prices = hre.viewData()
      const [userInfos, assetInfos, { scdp }] = await Promise.all([
        hre.Diamond.sDataAccounts(
          prices,
          f.usersArr.map(u => u.address),
          [f.Collateral.address, f.Collateral8Dec.address],
        ),
        hre.Diamond.sDataAssets(prices, [f.Collateral.address, f.Collateral8Dec.address]),
        hre.Diamond.aDataProtocol(prices),
      ])

      for (const userInfo of userInfos) {
        expect(userInfo.deposits[0].amount).eq(depositAmount18Dec)
        expect(userInfo.deposits[0].val).eq(expectedValueUnadjusted)
        expect(userInfo.deposits[1].amount).eq(depositAmount8Dec)
        expect(userInfo.deposits[1].val).eq(expectedValueUnadjusted8Dec)

        expect(userInfo.totals.valColl).eq(expectedValueUnadjusted.add(expectedValueUnadjusted8Dec))
      }

      expect(assetInfos[0].amountColl).eq(depositAmount18Dec.mul(f.usersArr.length))
      expect(assetInfos[1].amountColl).eq(depositAmount8Dec.mul(f.usersArr.length))

      // WITH_FACTORS global
      const valueTotalAdjusted = expectedValueAdjusted.mul(f.usersArr.length)
      const valueTotalAdjusted8Dec = expectedValueAdjusted8Dec.mul(f.usersArr.length)
      const valueAdjusted = valueTotalAdjusted.add(valueTotalAdjusted8Dec)

      expect(assetInfos[0].valColl).eq(valueTotalAdjusted)
      expect(assetInfos[1].valCollAdj).eq(valueTotalAdjusted8Dec)

      expect(scdp.totals.valCollAdj).eq(valueAdjusted)
      expect(scdp.totals.valDebt).eq(0)
      expect(scdp.totals.cr).eq(maxUint256)

      // WITHOUT_FACTORS global
      const valueTotalUnadjusted = expectedValueUnadjusted.mul(f.usersArr.length)
      const valueTotalUnadjusted8Dec = expectedValueUnadjusted8Dec.mul(f.usersArr.length)
      const valueUnadjusted = valueTotalUnadjusted.add(valueTotalUnadjusted8Dec)

      expect(assetInfos[0].valColl).eq(valueTotalUnadjusted)
      expect(assetInfos[1].valColl).eq(valueTotalUnadjusted8Dec)

      expect(scdp.totals.valColl).eq(valueUnadjusted)
      expect(scdp.totals.valDebt).eq(0)
      expect(scdp.totals.cr).eq(maxUint256)
    })
  })
  describe('#Withdraw', async () => {
    beforeEach(async function () {
      await Promise.all(
        f.usersArr.map(async user => {
          const User = hre.Diamond.connect(user)
          await hre.Diamond.setGlobalIncome(f.Collateral.address)
          await User.depositSCDP(user.address, f.Collateral.address, depositAmount18Dec)
          await hre.Diamond.setGlobalIncome(f.Collateral8Dec.address)
          await User.depositSCDP(user.address, f.Collateral8Dec.address, depositAmount8Dec)
        }),
      )
    })

    it('should be able to withdraw full collateral of multiple assets', async function () {
      await Promise.all(
        f.usersArr.map(async user => {
          const User = hre.Diamond.connect(user)
          return Promise.all([
            User.withdrawSCDP(
              {
                account: user.address,
                collateral: f.Collateral.address,
                amount: depositAmount18Dec,
                receiver: user.address,
              },
              hre.updateData(),
            ),
            User.withdrawSCDP(
              {
                account: user.address,
                collateral: f.Collateral8Dec.address,
                amount: depositAmount8Dec,
                receiver: user.address,
              },
              hre.updateData(),
            ),
          ])
        }),
      )

      expect(await f.Collateral.balanceOf(hre.Diamond.address)).eq(0)

      const prices = hre.viewData()
      const [userInfos, assetInfos, { scdp }] = await Promise.all([
        hre.Diamond.sDataAccounts(
          prices,
          f.usersArr.map(u => u.address),
          [f.Collateral.address, f.Collateral8Dec.address],
        ),
        hre.Diamond.sDataAssets(prices, [f.Collateral.address, f.Collateral8Dec.address]),
        hre.Diamond.aDataProtocol(prices),
      ])

      for (const userInfo of userInfos) {
        expect(await f.Collateral.balanceOf(userInfo.addr)).eq(depositAmount18Dec)
        expect(userInfo.deposits[0].amount).eq(0)
        expect(userInfo.deposits[0].amountFees).eq(0)
        expect(userInfo.deposits[1].amount).eq(0)
        expect(userInfo.deposits[1].amountFees).eq(0)
        expect(userInfo.totals.valColl).eq(0)
      }

      for (const assetInfo of assetInfos) {
        expect(assetInfo.valColl).eq(0)
        expect(assetInfo.amountColl).eq(0)
        expect(assetInfo.amountSwapDeposit).eq(0)
      }
      expect(scdp.totals.valColl).eq(0)
      expect(scdp.totals.valDebt).eq(0)
      expect(scdp.totals.cr).eq(0)
    })

    it('should be able to withdraw partial collateral of multiple assets', async function () {
      const partialWithdraw = depositAmount18Dec.div(f.usersArr.length)
      const partialWithdraw8Dec = depositAmount8Dec.div(f.usersArr.length)

      const expectedValueUnadjusted = toBig(f.CollateralPrice.num(8) * depositAmount, 8)
        .mul(200)
        .div(300)
      const expectedValueAdjusted = toBig(f.CollateralPrice.num(8) * 1 * depositAmount, 8)
        .mul(200)
        .div(300) // cfactor = 1

      const expectedValueUnadjusted8Dec = toBig(f.CollateralPrice.num(8) * depositAmount, 8)
        .mul(200)
        .div(300)
      const expectedValueAdjusted8Dec = toBig(f.CollateralPrice.num(8) * 0.8 * depositAmount, 8)
        .mul(200)
        .div(300) // cfactor = 0.8

      await Promise.all(
        f.usersArr.map(async user => {
          const User = hre.Diamond.connect(user)
          return Promise.all([
            User.withdrawSCDP(
              {
                account: user.address,
                collateral: f.Collateral.address,
                amount: partialWithdraw,
                receiver: user.address,
              },
              hre.updateData(),
            ),
            User.withdrawSCDP(
              {
                account: user.address,
                collateral: f.Collateral8Dec.address,
                amount: partialWithdraw8Dec,
                receiver: user.address,
              },
              hre.updateData(),
            ),
          ])
        }),
      )

      const [collateralBalanceAfter, collateral8DecBalanceAfter, { scdp }, assetInfos, userInfos] = await Promise.all([
        f.Collateral.balanceOf(hre.Diamond.address),
        f.Collateral8Dec.balanceOf(hre.Diamond.address),
        hre.Diamond.aDataProtocol(hre.viewData()),
        hre.Diamond.sDataAssets(hre.viewData(), [f.Collateral.address, f.Collateral8Dec.address]),
        hre.Diamond.sDataAccounts(
          hre.viewData(),
          f.usersArr.map(u => u.address),
          [f.Collateral.address, f.Collateral8Dec.address],
        ),
      ])
      for (const userInfo of userInfos) {
        const [balance18Dec, balance8Dec] = await Promise.all([
          f.Collateral.balanceOf(userInfo.addr),
          f.Collateral8Dec.balanceOf(userInfo.addr),
        ])

        expect(balance18Dec).eq(partialWithdraw)
        expect(balance8Dec).eq(partialWithdraw8Dec)
        expect(userInfo.deposits[0].amount).eq(depositAmount18Dec.sub(partialWithdraw))
        expect(userInfo.deposits[0].amountFees).eq(0)

        expect(userInfo.deposits[1].amount).eq(depositAmount8Dec.sub(partialWithdraw8Dec))
        expect(userInfo.deposits[1].amountFees).eq(0)

        expect(userInfo.totals.valColl).to.closeTo(
          expectedValueUnadjusted.add(expectedValueUnadjusted8Dec),
          toBig(0.00001, 8),
        )
      }

      expect(collateralBalanceAfter).to.closeTo(toBig(2000), 1)
      expect(collateral8DecBalanceAfter).to.closeTo(toBig(2000, 8), 1)

      expect(assetInfos[0].amountColl).to.closeTo(toBig(2000), 1)
      expect(assetInfos[1].amountColl).to.closeTo(toBig(2000, 8), 1)

      expect(assetInfos[0].valColl).to.closeTo(expectedValueUnadjusted.mul(f.usersArr.length), 20)
      expect(assetInfos[0].valCollAdj).to.closeTo(expectedValueAdjusted.mul(f.usersArr.length), 20)

      expect(assetInfos[1].valColl).to.closeTo(expectedValueUnadjusted8Dec.mul(f.usersArr.length), 20)
      expect(assetInfos[1].valCollAdj).to.closeTo(expectedValueAdjusted8Dec.mul(f.usersArr.length), 20)
      const totalValueRemaining = expectedValueUnadjusted8Dec
        .mul(f.usersArr.length)
        .add(expectedValueUnadjusted.mul(f.usersArr.length))

      expect(scdp.totals.valColl).to.closeTo(totalValueRemaining, 20)
      expect(scdp.totals.valDebt).eq(0)
      expect(scdp.totals.cr).eq(maxUint256)
    })
  })
  describe('#Fee Distribution', () => {
    let incomeCumulator: SignerWithAddress
    let IncomeCumulator: KopioCore

    beforeEach(async function () {
      incomeCumulator = hre.users.deployer
      IncomeCumulator = hre.Diamond.connect(incomeCumulator)
      await f.Collateral.setBalance(incomeCumulator, depositAmount18Dec.mul(f.usersArr.length), hre.Diamond.address)
    })

    it('should be able to cumulate fees into deposits', async function () {
      await hre.Diamond.setGlobalIncome(f.Collateral.address)
      const feePerUser = depositAmount18Dec
      const feesToCumulate = feePerUser.mul(f.usersArr.length)
      const feePerUserValue = toBig(f.CollateralPrice.num(8) * depositAmount, 8)
      const expectedDepositValue = toBig(f.CollateralPrice.num(8) * depositAmount, 8)

      // deposit some
      await Promise.all(
        f.usersArr.map(signer =>
          hre.Diamond.connect(signer).depositSCDP(signer.address, f.Collateral.address, depositAmount18Dec),
        ),
      )

      // cumulate some income
      await IncomeCumulator.addGlobalIncome(f.Collateral.address, feesToCumulate)

      // check that the fees are cumulated
      for (const data of await hre.Diamond.sDataAccounts(
        hre.viewData(),
        f.usersArr.map(u => u.address),
        [f.Collateral.address],
      )) {
        expect(data.deposits[0].val).eq(expectedDepositValue)
        expect(data.deposits[0].valFees).eq(feePerUserValue)
        expect(data.totals.valColl).eq(expectedDepositValue)
        expect(data.totals.valFees).eq(feePerUserValue)
      }

      // withdraw principal
      await Promise.all(
        f.usersArr.map(async signer =>
          hre.Diamond.connect(signer).withdrawSCDP(
            {
              account: signer.address,
              collateral: f.Collateral.address,
              amount: depositAmount18Dec,
              receiver: signer.address,
            },
            hre.updateData(),
          ),
        ),
      )

      const prices = hre.viewData()

      for (const user of await hre.Diamond.sDataAccounts(
        prices,
        f.usersArr.map(u => u.address),
        [f.Collateral.address],
      )) {
        const balance = await f.Collateral.balanceOf(user.addr)
        expect(user.deposits[0].val).eq(0)
        expect(user.deposits[0].valFees).eq(0)
        expect(user.totals.valFees).eq(0)
        expect(user.totals.valColl).eq(0)
        expect(balance).eq(depositAmount18Dec.add(feePerUser))
      }

      const [[assetInfo], { scdp }, balance] = await Promise.all([
        hre.Diamond.sDataAssets(prices, [f.Collateral.address]),
        hre.Diamond.aDataProtocol(prices),
        f.Collateral.balanceOf(hre.Diamond.address),
      ])

      expect(balance).eq(0)
      expect(assetInfo.amountColl).eq(0)
      expect(assetInfo.valColl).eq(0)
      expect(assetInfo.valCollAdj).eq(0)
      expect(scdp.totals.valColl).eq(0)

      // nothing left in protocol.
      const [collBalProtocol, [assetInfoFinal]] = await Promise.all([
        f.Collateral.balanceOf(hre.Diamond.address),
        hre.Diamond.sDataAssets(prices, [f.Collateral.address]),
      ])
      expect(collBalProtocol).eq(0)
      expect(assetInfoFinal.amountColl).eq(0)
      expect(assetInfoFinal.valColl).eq(0)
      expect(assetInfoFinal.valCollAdj).eq(0)
    })
  })
  describe('#Swap', () => {
    beforeEach(async function () {
      await Promise.all(f.usersArr.map(signer => f.Collateral.setBalance(signer, toBig(1_000_000))))
      await f.ONE.setBalance(f.swapper, toBig(10_000))
      await f.ONE.setBalance(f.depositor, toBig(10_000))
      await f.Depositor.depositSCDP(
        f.depositor.address,
        f.ONE.address,
        depositAmount18Dec, // $10k
      )
    })
    it('should have collateral in pool', async function () {
      const { scdp } = await hre.Diamond.aDataProtocol(hre.viewData())
      expect(scdp.totals.valColl).eq(toBig(depositAmount, 8))
      expect(scdp.totals.valDebt).eq(0)
      expect(scdp.totals.cr).eq(maxUint256)
    })

    it('should be able to preview a swap', async function () {
      const swapAmount = toBig(1)

      expect((await f.Kopio2.getPrice()).pyth).eq(f.Kopio2Price)

      const feePercentageProtocol =
        Number(f.ONE.config.assetStruct.protocolFeeShareSCDP) + Number(f.Kopio2.config.assetStruct.protocolFeeShareSCDP)

      const expectedTotalFee = swapAmount.percentMul(f.KOPIO_ONE_ROUTE_FEE)
      const expectedProtocolFee = expectedTotalFee.percentMul(feePercentageProtocol)
      const expectedFee = expectedTotalFee.sub(expectedProtocolFee)
      const amountInAfterFees = swapAmount.sub(expectedTotalFee)

      const expectedAmountOut = amountInAfterFees.wadMul(f.ONEPrice).wadDiv(f.Kopio2Price)
      const [amountOut, feeAmount, feeAmountProtocol] = await hre.Diamond.previewSwapSCDP(
        f.ONE.address,
        f.Kopio2.address,
        swapAmount,
      )
      expect(amountOut).eq(expectedAmountOut)
      expect(feeAmount).eq(expectedFee)
      expect(feeAmountProtocol).eq(expectedProtocolFee)
    })

    it('should be able to swap, shared debt == 0 | swap collateral == 0', async function () {
      const swapAmount = toBig(1) // $1
      const oneInAfterFees = swapAmount.sub(swapAmount.percentMul(f.KOPIO_ONE_ROUTE_FEE))

      const expectedAmountOut = oneInAfterFees.wadMul(f.ONEPrice).wadDiv(f.Kopio2Price)
      const tx = await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      const event = await getNamedEvent<SwapEvent>(tx, 'Swap')
      expect(event.args.who).eq(f.swapper.address)
      expect(event.args.assetIn).eq(f.ONE.address)
      expect(event.args.assetOut).eq(f.Kopio2.address)
      expect(event.args.amountIn).eq(swapAmount)
      expect(event.args.amountOut).eq(expectedAmountOut)

      const prices = hre.viewData()
      const [Kopio2Bal, ONEBalance, swapperInfos, assetInfos, { scdp }] = await Promise.all([
        f.Kopio2.balanceOf(f.swapper.address),
        f.ONE.balanceOf(f.swapper.address),
        hre.Diamond.sDataAccounts(prices, [f.swapper.address], [f.Kopio2.address, f.ONE.address]),
        hre.Diamond.sDataAssets(prices, [f.Kopio2.address, f.ONE.address]),
        hre.Diamond.aDataProtocol(prices),
      ])
      const swapperInfo = swapperInfos[0]
      expect(Kopio2Bal).eq(expectedAmountOut)
      expect(ONEBalance).eq(toBig(10_000).sub(swapAmount))

      expect(swapperInfo.deposits[0].val).eq(0)
      expect(swapperInfo.deposits[1].val).eq(0)

      expect(assetInfos[0].amountDebt).eq(expectedAmountOut)
      expect(assetInfos[1].amountSwapDeposit).eq(oneInAfterFees)

      const expectedDepositValue = toBig(depositAmount, 8).add(oneInAfterFees.wadMul(f.ONEPrice))
      expect(assetInfos[1].valColl).eq(expectedDepositValue)
      expect(assetInfos[0].valDebt).eq(expectedAmountOut.wadMul(f.Kopio2Price))

      expect(scdp.totals.valColl).eq(expectedDepositValue)
      expect(scdp.totals.valDebt).eq(expectedAmountOut.wadMul(f.Kopio2Price))
      expect(scdp.totals.cr).eq(expectedDepositValue.percentDiv(expectedAmountOut.wadMul(f.Kopio2Price)))
    })

    it('should be able to swap, shared debt == assetsIn | swap collateral == assetsOut', async function () {
      const swapAmount = toBig(100) // $100
      const swapAmountAsset = swapAmount
        .percentMul(1e4 - Number(f.KOPIO_ONE_ROUTE_FEE))
        .wadMul(f.ONEPrice.wadDiv(f.Kopio2Price))
      const expectedONEOut = swapAmountAsset
        .percentMul(1e4 - f.KOPIO_ONE_ROUTE_FEE)
        .wadMul(f.Kopio2Price)
        .wadDiv(f.ONEPrice)

      // deposit to protocol for minting first
      await depositCollateral({
        user: f.swapper,
        asset: f.ONE,
        amount: toBig(100),
      })

      await mintKopio({
        user: f.swapper,
        asset: f.Kopio2,
        amount: toBig(0.1), // min allowed
      })

      const { scdp } = await hre.Diamond.aDataProtocol(hre.viewData())

      expect(scdp.totals.valColl).eq(initialDepositValue)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      // the swap that clears debt
      const tx = await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        amountIn: swapAmountAsset,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      const [event, assetInfos] = await Promise.all([
        getNamedEvent<SwapEvent>(tx, 'Swap'),
        hre.Diamond.sDataAssets(hre.viewData(), [f.ONE.address, f.Kopio2.address]),
      ])

      expect(event.args.who).eq(f.swapper.address)
      expect(event.args.assetIn).eq(f.Kopio2.address)
      expect(event.args.assetOut).eq(f.ONE.address)
      expect(event.args.amountIn).eq(swapAmountAsset)
      expect(event.args.amountOut).eq(expectedONEOut)

      expect(assetInfos[0].amountSwapDeposit).eq(0)
      expect(assetInfos[0].valColl).eq(initialDepositValue)

      expect(assetInfos[1].valDebt).eq(0)
      expect(assetInfos[1].amountDebt).eq(0)

      const { scdp: scdpAfter } = await hre.Diamond.aDataProtocol(hre.viewData())
      expect(scdpAfter.totals.valColl).eq(toBig(1000, 8))
      expect(scdpAfter.totals.valDebt).eq(0)
      expect(scdpAfter.totals.cr).eq(maxUint256)
    })

    it('should be able to swap, debt > assetsIn | swap deposits > assetsOut', async function () {
      const swapAmount = toBig(1) // $1
      const swapValue = toBig(1, 8)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      const [assetInfoONE] = await hre.Diamond.sDataAssets(hre.viewData(), [f.ONE.address])
      const feeValueFirstSwap = swapValue.percentMul(f.KOPIO_ONE_ROUTE_FEE)
      const valueInAfterFees = swapValue.sub(feeValueFirstSwap)
      expect(assetInfoONE.valColl).eq(depositValue.add(valueInAfterFees))

      const expectedSwapDeposits = valueInAfterFees.num(8).ebn(18)
      expect(assetInfoONE.amountSwapDeposit).eq(expectedSwapDeposits)

      const swapAmountSecond = toBig(0.009) // this is $0.90, so less than $0.96 since we want to ensure debt > assetsIn | swap deposits > assetsOut
      const swapValueSecond = swapAmountSecond.wadMul(f.Kopio2Price)
      const feeValueSecondSwap = swapValueSecond.sub(swapValueSecond.percentMul(f.KOPIO_ONE_ROUTE_FEE))
      const expectedONEOut = feeValueSecondSwap.wadDiv(f.ONEPrice) // 0.8685

      const tx = await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        amountIn: swapAmountSecond,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      const event = await getNamedEvent<SwapEvent>(tx, 'Swap')

      expect(event.args.who).eq(f.swapper.address)
      expect(event.args.assetIn).eq(f.Kopio2.address)
      expect(event.args.assetOut).eq(f.ONE.address)
      expect(event.args.amountIn).eq(swapAmountSecond)
      expect(event.args.amountOut).eq(expectedONEOut)

      const [depositValKopio2, depositValueONE, assetInfos, { scdp }] = await Promise.all([
        f.Swapper.getAccountDepositValueSCDP(f.swapper.address, f.Kopio2.address),
        f.Swapper.getAccountDepositValueSCDP(f.swapper.address, f.ONE.address),
        hre.Diamond.sDataAssets(hre.viewData(), [f.ONE.address, f.Kopio2.address]),
        hre.Diamond.aDataProtocol(hre.viewData()),
      ])

      expect(depositValKopio2).eq(0)
      expect(depositValueONE).eq(0)

      const expectedSwapDepositsAfter = expectedSwapDeposits.sub(toBig(0.9))
      const expectedSwapDepositsValue = expectedSwapDepositsAfter.wadMul(assetInfoONE.price)

      expect(assetInfos[0].amountSwapDeposit).eq(expectedSwapDepositsAfter)
      expect(assetInfos[0].valColl).eq(toBig(depositAmount, 8).add(expectedSwapDepositsValue))
      expect(assetInfos[1].valDebt).eq(expectedSwapDepositsValue)

      const expectedDebtAfter = expectedSwapDepositsValue.wadDiv((await f.Kopio2.getPrice()).pyth)
      expect(assetInfos[0].amountDebt).eq(0)
      expect(assetInfos[1].amountDebt).eq(expectedDebtAfter)

      const expectedCollateralValue = expectedSwapDepositsValue.add(depositAmount.ebn(8))
      expect(scdp.totals.valColl).eq(expectedCollateralValue) // swap deposits + collateral deposited
      expect(scdp.totals.valDebt).eq(expectedSwapDepositsValue) //
      expect(scdp.totals.cr).eq(expectedCollateralValue.percentDiv(expectedSwapDepositsValue))
    })

    it('should be able to swap, debt < assetsIn | swap deposits < assetsOut', async function () {
      const swapAmountONE = toBig(100) // $100
      const swapAmountKopio = toBig(2) // $200
      const swapValue = 200
      const firstSwapFeeAmount = swapAmountONE.percentMul(f.KOPIO_ONE_ROUTE_FEE)
      const expectedONEOutSecondSwap = swapAmountKopio
        .sub(swapAmountKopio.percentMul(f.KOPIO_ONE_ROUTE_FEE))
        .wadMul(f.Kopio2Price)
        .wadDiv(f.ONEPrice)
      const kopioOutFirstSwap = swapAmountONE.sub(firstSwapFeeAmount).wadMul(f.ONEPrice).wadDiv(f.Kopio2Price)

      const kopioOutFirstSwapValue = kopioOutFirstSwap.wadMul(f.Kopio2Price)
      // deposit to protocol for minting first
      await depositCollateral({
        user: f.swapper,
        asset: f.ONE,
        amount: toBig(400),
      })
      const ICDPMintAmount = toBig(1.04)
      await mintKopio({
        user: f.swapper,
        asset: f.Kopio2,
        amount: ICDPMintAmount,
      })

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmountONE,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      const expectedSwapDeposits = swapAmountONE.sub(firstSwapFeeAmount)
      const { scdp } = await hre.Diamond.aDataProtocol(hre.viewData())
      expect(await f.Swapper.getSwapDepositsSCDP(f.ONE.address)).eq(expectedSwapDeposits)
      expect(scdp.totals.valColl).eq(depositAmount.ebn().add(expectedSwapDeposits).wadMul(f.ONEPrice))

      // the swap that matters, here user has 0.96 (previous swap) + 1.04 (mint). expecting 192 one from swap.
      const [expectedAmountOut] = await f.Swapper.previewSwapSCDP(f.Kopio2.address, f.ONE.address, swapAmountKopio)
      expect(expectedAmountOut).eq(expectedONEOutSecondSwap)
      const tx = await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        amountIn: swapAmountKopio,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      const event = await getNamedEvent<SwapEvent>(tx, 'Swap')

      expect(event.args.who).eq(f.swapper.address)
      expect(event.args.assetIn).eq(f.Kopio2.address)
      expect(event.args.assetOut).eq(f.ONE.address)
      expect(event.args.amountIn).eq(swapAmountKopio)
      expect(event.args.amountOut).eq(expectedONEOutSecondSwap)

      const assetInfos = await hre.Diamond.sDataAssets(hre.viewData(), [f.ONE.address, f.Kopio2.address])
      // f.ONE deposits sent in swap
      const acocuntPrincipalDepositsONE = await f.Swapper.getAccountDepositSCDP(f.depositor.address, f.ONE.address)

      expect(assetInfos[0].amountSwapDeposit).eq(0) // half of 2 kopio
      expect(assetInfos[0].amountColl).eq(acocuntPrincipalDepositsONE)

      // Kopio debt is cleared
      expect(assetInfos[1].valDebt).eq(0)
      expect(assetInfos[1].amountDebt).eq(0)

      // ONE debt is issued
      const expectedOneDebtVal = toBig(swapValue, 8).sub(kopioOutFirstSwapValue)
      expect(assetInfos[0].valDebt).eq(expectedOneDebtVal)

      expect(assetInfos[0].amountDebt).eq(expectedOneDebtVal.wadDiv(f.ONEPrice))

      // kopio swap deposits
      const expectedSwapDepositValue = toBig(swapValue, 8).sub(kopioOutFirstSwapValue)
      expect(assetInfos[1].amountSwapDeposit).eq(toBig(2).sub(kopioOutFirstSwap))
      expect(assetInfos[1].valColl).eq(expectedSwapDepositValue) // asset price is $100

      const { scdp: scdpAfter } = await hre.Diamond.aDataProtocol(hre.viewData())
      const expectedCollateralValue = toBig(1000, 8).add(expectedSwapDepositValue)
      expect(scdpAfter.totals.valColl).eq(expectedCollateralValue)
      expect(scdpAfter.totals.valDebt).eq(expectedOneDebtVal)
      expect(scdpAfter.totals.cr).eq(expectedCollateralValue.percentDiv(expectedOneDebtVal))
    })

    it('cumulates fees on swap', async function () {
      const depositAmountNew = toBig(10000 - depositAmount)

      await f.ONE.setBalance(f.depositor, depositAmountNew)
      await f.Depositor.depositSCDP(
        f.depositor.address,
        f.ONE.address,
        depositAmountNew, // $10k
      )

      const swapAmount = toBig(2600)

      const feesBeforeSwap = await f.Swapper.getAccountFeesSCDP(f.depositor.address, f.ONE.address)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      const feesAfterSwap = await f.Swapper.getAccountFeesSCDP(f.depositor.address, f.ONE.address)
      expect(feesAfterSwap).to.gt(feesBeforeSwap)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        amountIn: f.Kopio2.balanceOf(f.swapper.address),
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      const feesAfterSecondSwap = await f.Swapper.getAccountFeesSCDP(f.depositor.address, f.ONE.address)
      expect(feesAfterSecondSwap).to.gt(feesAfterSwap)

      await f.Depositor.claimFeesSCDP(f.depositor.address, f.ONE.address, f.depositor.address)

      const [depositsAfter, feesAfter] = await Promise.all([
        f.Swapper.getAccountDepositSCDP(f.depositor.address, f.ONE.address),
        f.Swapper.getAccountFeesSCDP(f.depositor.address, f.ONE.address),
      ])

      expect(feesAfter).eq(0)

      expect(depositsAfter).eq(toBig(10000))

      await f.Depositor.withdrawSCDP(
        {
          account: f.depositor.address,
          collateral: f.ONE.address,
          amount: toBig(10000), // $10k f.ONE
          receiver: f.depositor.address,
        },
        hre.updateData(),
      )

      const [depositsAfterWithdraw, feesAfterWithdraw] = await Promise.all([
        f.Swapper.getAccountDepositValueSCDP(f.depositor.address, f.ONE.address),
        f.Swapper.getAccountFeesSCDP(f.depositor.address, f.ONE.address),
      ])

      expect(depositsAfterWithdraw).eq(0)

      expect(feesAfterWithdraw).eq(0)
    })
  })
  describe('#Liquidations', () => {
    beforeEach(async function () {
      for (const signer of f.usersArr) {
        await f.Collateral.setBalance(signer, toBig(1_000_000))
      }
      await f.ONE.setBalance(f.swapper, toBig(10_000))
      await f.ONE.setBalance(f.depositor2, toBig(10_000))
      await hre.Diamond.setGlobalIncome(f.Collateral.address)

      await f.Depositor.depositSCDP(
        f.depositor.address,
        f.Collateral.address,
        depositAmount18Dec, // $10k
      )

      await hre.Diamond.setGlobalIncome(f.Collateral8Dec.address)
      await f.Depositor.depositSCDP(
        f.depositor.address,
        f.Collateral8Dec.address,
        depositAmount8Dec, // $8k
      )

      await hre.Diamond.setGlobalIncome(f.ONE.address)
      f.Depositor2.depositSCDP(
        f.depositor2.address,
        f.ONE.address,
        depositAmount18Dec, // $8k
      )
    })
    it('should identify if the pool is not underwater', async function () {
      const swapAmount = toBig(2600) // $1

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })

      expect(await hre.Diamond.getLiquidatableSCDP()).to.be.false
    })

    //  test not passing
    it('should revert liquidations if the pool is not underwater', async function () {
      const swapAmount = toBig(2600) // $1

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      expect(await hre.Diamond.getLiquidatableSCDP()).to.be.false

      await f.Kopio2.setBalance(hre.users.liquidator, toBig(1_000_000))

      await expect(
        f.Liquidator.liquidateSCDP(
          {
            kopio: f.Kopio2.address,
            amount: toBig(7.7),
            collateral: f.Collateral8Dec.address,
          },
          hre.updateData(),
        ),
      ).to.be.revertedWithCustomError(Errors(hre), 'COLLATERAL_VALUE_GREATER_THAN_REQUIRED')
    })

    it('should identify if the pool is underwater', async function () {
      const swapAmount = toBig(2600)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      await f.Collateral.setPrice(f.CollateralPrice.num(8) / 1000)
      await f.Collateral8Dec.setPrice(f.CollateralPrice.num(8) / 1000)

      const [{ scdp }, liquidatable] = await Promise.all([
        hre.Diamond.aDataProtocol(hre.viewData()),
        hre.Diamond.getLiquidatableSCDP(),
      ])

      expect(scdp.totals.cr).to.be.lt(scdp.LT)
      expect(liquidatable).to.be.true
    })

    it('should allow liquidating the underwater pool', async function () {
      const swapAmount = toBig(2600)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      const newAssetPrice = 500
      await f.Kopio2.setPrice(newAssetPrice)

      const [scdpParams, maxLiquidatable, kopioPrice, { scdp: scdpBefore }] = await Promise.all([
        hre.Diamond.getGlobalParameters(),
        hre.Diamond.getMaxLiqValueSCDP(f.Kopio2.address, f.Collateral8Dec.address),
        f.Kopio2.getPrice(),
        hre.Diamond.aDataProtocol(hre.viewData()),
      ])
      const repayAmount = maxLiquidatable.repayValue.wadDiv(kopioPrice.pyth)

      await f.Kopio2.setBalance(hre.users.liquidator, repayAmount.add((1e18).toString()))
      expect(scdpBefore.totals.cr).to.lt(scdpParams.liquidationThreshold)
      expect(scdpBefore.totals.cr).to.gt(1e4)

      // Liquidate the shared CDP
      const tx = await f.Liquidator.liquidateSCDP(
        {
          kopio: f.Kopio2.address,
          amount: repayAmount,
          collateral: f.Collateral8Dec.address,
        },
        hre.updateData(),
      )

      // Check the state after liquidation
      const [{ scdp: scdpAfter }, liquidatableAfter] = await Promise.all([
        hre.Diamond.aDataProtocol(hre.viewData()),
        hre.Diamond.getLiquidatableSCDP(),
      ])
      expect(scdpAfter.totals.cr).to.gt(scdpParams.liquidationThreshold)

      expect(liquidatableAfter).eq(false)

      // Shared CDP should not be liquidatable since it is above the threshold
      await expect(
        f.Liquidator.liquidateSCDP(
          {
            kopio: f.Kopio2.address,
            amount: repayAmount,
            collateral: f.Collateral8Dec.address,
          },
          hre.updateData(),
        ),
      ).to.be.revertedWithCustomError(Errors(hre), 'COLLATERAL_VALUE_GREATER_THAN_REQUIRED')

      // Check what was emitted in the event
      const event = await getNamedEvent<SCDPLiquidationOccuredEvent>(tx, 'SCDPLiquidationOccured')
      const expectedSeizeAmount = repayAmount
        .wadMul(toBig(newAssetPrice, 8))
        .percentMul(1.05e4)
        .wadDiv(f.CollateralPrice)
        .div(10 ** 10)

      expect(event.args.liquidator).eq(hre.users.liquidator.address)
      expect(event.args.seizeAmount).eq(expectedSeizeAmount)
      expect(event.args.repayAmount).eq(repayAmount)
      expect(event.args.seizeCollateral).eq(f.Collateral8Dec.address)
      expect(event.args.repayKopio).eq(f.Kopio2.address)

      // Check account state changes
      const expectedDepositsAfter = depositAmount8Dec.sub(event.args.seizeAmount)
      expect(expectedDepositsAfter).to.be.lt(depositAmount8Dec)

      const [principalDeposits, fees, params] = await Promise.all([
        hre.Diamond.getAccountDepositSCDP(f.depositor.address, f.Collateral8Dec.address),
        hre.Diamond.getAccountFeesSCDP(f.depositor.address, f.Collateral8Dec.address),
        hre.Diamond.getGlobalParameters(),
      ])
      expect(principalDeposits).eq(expectedDepositsAfter)
      expect(fees).eq(0)

      // Sanity checking that users should be able to withdraw what is left
      await hre.Diamond.setGlobalIncome(f.Collateral.address)
      await f.Depositor.depositSCDP(f.depositor.address, f.Collateral.address, depositAmount18Dec.mul(10))
      const { scdp } = await hre.Diamond.aDataProtocol(hre.viewData())
      expect(scdp.totals.cr).to.gt(params.minCollateralRatio)
      await expect(
        f.Depositor.withdrawSCDP(
          {
            account: f.depositor.address,
            collateral: f.Collateral8Dec.address,
            amount: expectedDepositsAfter,
            receiver: f.depositor.address,
          },
          hre.updateData(),
        ),
      ).to.not.be.reverted
      const [principalEnd, feesAfter] = await Promise.all([
        hre.Diamond.getAccountDepositSCDP(f.depositor.address, f.Collateral8Dec.address),
        hre.Diamond.getAccountFeesSCDP(f.depositor.address, f.Collateral8Dec.address),
      ])
      expect(principalEnd).eq(0)
      expect(feesAfter).eq(0)
    })
  })
  describe('#Error', () => {
    beforeEach(async function () {
      await Promise.all(f.usersArr.map(signer => f.Collateral.setBalance(signer, toBig(1_000_000))))
      await f.ONE.setBalance(f.swapper, toBig(10_000))
      await f.ONE.setBalance(f.depositor, hre.ethers.BigNumber.from(1))

      await hre.Diamond.setGlobalIncome(f.Collateral.address)
      await f.Depositor.depositSCDP(
        f.depositor.address,
        f.Collateral.address,
        depositAmount18Dec, // $10k
      )
      await hre.Diamond.setGlobalIncome(f.ONE.address)
      await f.Depositor.depositSCDP(f.depositor.address, f.ONE.address, 1)
    })
    it('should revert depositing unsupported tokens', async function () {
      const [UnsupportedToken] = await hre.deploy('ERC20Mock', {
        args: ['UnsupportedToken', 'UnsupportedToken', 18, toBig(1)],
      })
      await UnsupportedToken.approve(hre.Diamond.address, hre.ethers.constants.MaxUint256)
      const { deployer } = await hre.getNamedAccounts()
      await expect(hre.Diamond.depositSCDP(deployer, UnsupportedToken.address, 1))
        .to.be.revertedWithCustomError(Errors(hre), 'NOT_CUMULATED')
        .withArgs(['UnsupportedToken', UnsupportedToken.address])
    })
    it('should revert withdrawing without deposits', async function () {
      const withdrawAmount = 1
      await expect(
        f.Swapper.withdrawSCDP(
          {
            account: f.swapper.address,
            collateral: f.Collateral.address,
            amount: withdrawAmount,
            receiver: f.swapper.address,
          },
          hre.updateData(),
        ),
      )
        .to.be.revertedWithCustomError(Errors(hre), 'NO_DEPOSITS')
        .withArgs(f.swapper.address, f.Collateral.errorId)
    })

    it('should revert withdrawals below MCR', async function () {
      const swapAmount = toBig(1000) // $1000
      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.ONE.address,
        assetOut: f.Kopio2.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      }) // generates the debt
      const deposits = await f.Swapper.getAccountDepositSCDP(f.depositor.address, f.Collateral.address)
      await expect(
        f.Depositor.withdrawSCDP(
          {
            account: f.depositor.address,
            collateral: f.Collateral.address,
            amount: deposits,
            receiver: f.depositor.address,
          },
          hre.updateData(),
        ),
      )
        .to.be.revertedWithCustomError(Errors(hre), 'COLLATERAL_TOO_LOW')
        .withArgs(960e8, 4800e8, 5e4)
    })

    it('should revert withdrawals of swap owned collateral deposits', async function () {
      const swapAmount = toBig(1)
      await f.Kopio2.setBalance(f.swapper, swapAmount)

      await f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      const deposits = await f.Swapper.getSwapDepositsSCDP(f.Kopio2.address)
      expect(deposits).to.be.gt(0)
      await expect(
        f.Swapper.withdrawSCDP(
          { account: f.swapper.address, collateral: f.Kopio2.address, amount: deposits, receiver: f.depositor.address },
          hre.updateData(),
        ),
      )
        .to.be.revertedWithCustomError(Errors(hre), 'NO_GLOBAL_DEPOSITS')
        .withArgs(f.Kopio2.errorId)
    })

    it('should revert swapping with price below minAmountOut', async function () {
      const swapAmount = toBig(1)
      await f.Kopio2.setBalance(f.swapper, swapAmount)
      const [amountOut] = await f.Swapper.previewSwapSCDP(f.Kopio2.address, f.ONE.address, swapAmount)
      await expect(
        f.Swapper.swapSCDP({
          receiver: f.swapper.address,
          assetIn: f.Kopio2.address,
          assetOut: f.ONE.address,
          amountIn: swapAmount,
          amountOutMin: amountOut.add(1),
          prices: hre.updateData(),
        }),
      )
        .to.be.revertedWithCustomError(Errors(hre), 'RECEIVED_LESS_THAN_DESIRED')
        .withArgs(f.ONE.errorId, amountOut, amountOut.add(1))
    })

    it('should revert swapping unsupported asset', async function () {
      const swapAmount = toBig(1)
      await f.Kopio2.setBalance(f.swapper, swapAmount)

      await expect(
        f.Swapper.swapSCDP({
          receiver: f.swapper.address,
          assetIn: f.Kopio2.address,
          assetOut: f.Collateral.address,
          amountIn: swapAmount,
          amountOutMin: 0,
          prices: hre.updateData(),
        }),
      )
        .to.be.revertedWithCustomError(Errors(hre), 'SWAP_ROUTE_NOT_ENABLED')
        .withArgs(f.Kopio2.errorId, f.Collateral.errorId)
    })
    it('should revert swapping a disabled route', async function () {
      const swapAmount = toBig(1)
      await f.Kopio2.setBalance(f.swapper, swapAmount)

      await hre.Diamond.setSwapRoute({
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        enabled: false,
      })
      await expect(
        f.Swapper.swapSCDP({
          receiver: f.swapper.address,
          assetIn: f.Kopio2.address,
          assetOut: f.ONE.address,
          amountIn: swapAmount,
          amountOutMin: 0,
          prices: hre.updateData(),
        }),
      )
        .to.be.revertedWithCustomError(Errors(hre), 'SWAP_ROUTE_NOT_ENABLED')
        .withArgs(f.Kopio2.errorId, f.ONE.errorId)
    })
    it('should revert swapping causes CDP to go below MCR', async function () {
      const swapAmount = toBig(1_500_000)
      await f.Kopio2.setBalance(f.swapper, swapAmount)
      const tx = f.Swapper.swapSCDP({
        receiver: f.swapper.address,
        assetIn: f.Kopio2.address,
        assetOut: f.ONE.address,
        amountIn: swapAmount,
        amountOutMin: 0,
        prices: hre.updateData(),
      })
      await expect(tx)
        .to.be.revertedWithCustomError(Errors(hre), 'COLLATERAL_TOO_LOW')
        .withArgs('15001000000000000', '75000000000000000', 5e4)
    })
  })
})
