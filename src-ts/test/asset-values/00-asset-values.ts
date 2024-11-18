import type { KopioCore } from '@/types/typechain'
import { expect } from '@test/chai'
import { type AssetValuesFixture, assetValuesFixture } from '@utils/test/fixtures'
import { toBig } from '@utils/values'

describe('Asset Amounts & Values', function () {
  let f: AssetValuesFixture
  let User: KopioCore

  beforeEach(async () => {
    f = await assetValuesFixture()
    f.user = hre.users.userEight
    User = hre.Diamond.connect(f.user)
  })

  describe('#Collateral Deposit Values', async () => {
    it('should return the correct deposit value with 18 decimals', async () => {
      const depositAmount = toBig(10)
      const expectedDepositValue = toBig(50, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 10
      await User.depositCollateral(f.user.address, f.CollateralAsset.address, depositAmount)
      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)
    })
    it('should return the correct deposit value with less than 18 decimals', async () => {
      const depositAmount = toBig(10, 8)
      const expectedDepositValue = toBig(50, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 10
      await User.depositCollateral(f.user.address, f.CollateralAsset8Dec.address, depositAmount)
      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)
    })
    it('should return the correct deposit value with over 18 decimals', async () => {
      const depositAmount = toBig(10, 21)
      const expectedDepositValue = toBig(50, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 10
      await User.depositCollateral(f.user.address, f.CollateralAsset21Dec.address, depositAmount)
      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)
    })

    it('should return the correct deposit value combination of different decimals', async () => {
      await User.depositCollateral(f.user.address, f.CollateralAsset.address, toBig(10))
      await User.depositCollateral(f.user.address, f.CollateralAsset8Dec.address, toBig(10, 8))
      await User.depositCollateral(f.user.address, f.CollateralAsset21Dec.address, toBig(10, 21))
      const expectedDepositValue = toBig(150, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 30
      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)
    })
  })

  describe('#Collateral Deposit Amount', async () => {
    it('should return the correct deposit amount with 18 decimals', async () => {
      const depositAmount = toBig(10)
      await User.depositCollateral(f.user.address, f.CollateralAsset.address, depositAmount)
      const deposits = await hre.Diamond.getAccountCollateralAmount(f.user.address, f.CollateralAsset.address)
      expect(deposits).eq(depositAmount)
      await User.withdrawCollateral(
        {
          account: f.user.address,
          asset: f.CollateralAsset.address,
          amount: depositAmount,
          receiver: f.user.address,
        },
        hre.updateData(),
      )
      const balance = await f.CollateralAsset.balanceOf(f.user.address)
      expect(balance).eq(toBig(f.startingBalance))
    })

    it('should return the correct deposit amount with less than 18 decimals', async () => {
      const depositAmount = toBig(10, 8)
      await User.depositCollateral(f.user.address, f.CollateralAsset8Dec.address, depositAmount)
      const deposits = await hre.Diamond.getAccountCollateralAmount(f.user.address, f.CollateralAsset8Dec.address)
      expect(deposits).eq(depositAmount)
      await User.withdrawCollateral(
        {
          account: f.user.address,
          asset: f.CollateralAsset8Dec.address,
          amount: depositAmount,
          receiver: f.user.address,
        },
        hre.updateData(),
      )
      const balance = await f.CollateralAsset8Dec.balanceOf(f.user.address)
      expect(balance).eq(toBig(f.startingBalance, 8))
    })

    it('should return the correct deposit value with over 18 decimals', async () => {
      const depositAmount = toBig(10, 21)
      await User.depositCollateral(f.user.address, f.CollateralAsset21Dec.address, depositAmount)
      const deposits = await hre.Diamond.getAccountCollateralAmount(f.user.address, f.CollateralAsset21Dec.address)
      expect(deposits).eq(depositAmount)
      await User.withdrawCollateral(
        {
          account: f.user.address,
          asset: f.CollateralAsset21Dec.address,
          amount: depositAmount,
          receiver: f.user.address,
        },
        hre.updateData(),
      )
      const balance = await f.CollateralAsset21Dec.balanceOf(f.user.address)
      expect(balance).eq(toBig(f.startingBalance, 21))
    })
  })

  describe('#Asset Debt Values', async () => {
    it('should return the correct debt value (+CR) with 18 decimal collateral', async () => {
      const depositAmount = toBig(10)
      await User.depositCollateral(f.user.address, f.CollateralAsset.address, depositAmount)

      const mintAmount = toBig(1)

      const expectedMintValue = toBig(20, f.oracleDecimals) // dFactor = 2, kopioPrice = 10, mintAmount = 1, openFee = 0.1

      await User.mintKopio(
        { account: f.user.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user.address },
        hre.updateData(),
      )
      const expectedDepositValue = toBig(49.5, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 10, openFee = 0.1

      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)

      const mintValue = await hre.Diamond.getAccountTotalDebtValue(f.user.address)
      expect(mintValue).eq(expectedMintValue)

      const assetValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)
      const dFactor = (await hre.Diamond.getAsset(f.Kopio.address)).dFactor
      expect(assetValue).eq(expectedMintValue.percentDiv(dFactor))

      const collateralRatio = await hre.Diamond.getAccountCollateralRatio(f.user.address)
      expect(collateralRatio).eq(expectedDepositValue.percentDiv(expectedMintValue)) // 2.475
    })
    it('should return the correct debt value (+CR) with less than 18 decimal collateral', async () => {
      const depositAmount = toBig(10, 8)
      await User.depositCollateral(f.user.address, f.CollateralAsset8Dec.address, depositAmount)

      const mintAmount = toBig(1)
      const expectedMintValue = toBig(20, f.oracleDecimals) // dFactor = 2, kopioPrice = 10, mintAmount = 1, openFee = 0.1

      await User.mintKopio(
        { account: f.user.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user.address },
        hre.updateData(),
      )
      const expectedDepositValue = toBig(49.5, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 10, openFee = 0.1

      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)

      const mintValue = await hre.Diamond.getAccountTotalDebtValue(f.user.address)
      expect(mintValue).eq(expectedMintValue)

      const assetValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)
      const dFactor = (await hre.Diamond.getAsset(f.Kopio.address)).dFactor
      expect(assetValue).eq(expectedMintValue.percentDiv(dFactor))

      const collateralRatio = await hre.Diamond.getAccountCollateralRatio(f.user.address)
      expect(collateralRatio).eq(expectedDepositValue.percentDiv(expectedMintValue)) // 2.475
    })
    it('should return the correct debt value (+CR) with more than 18 decimal collateral', async () => {
      const depositAmount = toBig(10, 21)
      await User.depositCollateral(f.user.address, f.CollateralAsset21Dec.address, depositAmount)

      const mintAmount = toBig(1)
      const expectedMintValue = toBig(20, f.oracleDecimals) // dFactor = 2, kopioPrice = 10, mintAmount = 1, openFee = 0.1

      await User.mintKopio(
        { account: f.user.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user.address },
        hre.updateData(),
      )
      const expectedDepositValue = toBig(49.5, f.oracleDecimals) // cfactor = 0.5, collateralPrice = 10, depositAmount = 10, openFee = 0.1

      const depositValue = await hre.Diamond.getAccountTotalCollateralValue(f.user.address)
      expect(depositValue).eq(expectedDepositValue)

      const mintValue = await hre.Diamond.getAccountTotalDebtValue(f.user.address)
      expect(mintValue).eq(expectedMintValue)

      const assetValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)
      const dFactor = (await hre.Diamond.getAsset(f.Kopio.address)).dFactor
      expect(assetValue).eq(expectedMintValue.percentDiv(dFactor))

      const collateralRatio = await hre.Diamond.getAccountCollateralRatio(f.user.address)
      expect(collateralRatio).eq(expectedDepositValue.percentDiv(expectedMintValue)) // 2.475
    })
  })
})
