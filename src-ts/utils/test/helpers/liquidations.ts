import optimized from '@utils/test/helpers/optimizations'
import { fromBig, toBig } from '@utils/values'
import { mintKopio } from './assets'
import { depositCollateral, depositMockCollateral } from './collaterals'
export const getLiqAmount = async (user: SignerWithAddress, kopio: TestKopioAsset, collateral: any, log = false) => {
  const [maxLiquidatableValue, kopioPrice] = await Promise.all([
    hre.Diamond.getMaxLiqValue(user.address, kopio.address, collateral.address),
    kopio.getPrice(),
  ])

  if (log) {
    const [accMinCollVal, accCollVal, ratio, debt, collateralPrice] = await Promise.all([
      hre.Diamond.getAccountMinCollateralAtRatio(user.address, optimized.getLT()),
      hre.Diamond.getAccountTotalCollateralValue(user.address),
      hre.Diamond.getAccountCollateralRatio(user.address),
      hre.Diamond.getAccountDebtAmount(user.address, kopio.address),
      collateral.getPrice(),
    ])
    console.table({
      kopioPrice,
      collateralPrice,
      accCollVal,
      accMinCollVal,
      ratio,
      valueUnder: fromBig(accMinCollVal.sub(accCollVal), 8),
      debt,
      maxValue: maxLiquidatableValue,
      maxAmount: maxLiquidatableValue.repayValue.wadDiv(kopioPrice.pyth),
    })
  }

  return maxLiquidatableValue.repayValue.wadDiv(kopioPrice.pyth)
}

export const liquidate = async (
  user: SignerWithAddress,
  kopio: TestKopioAsset,
  collateral: TestExtAsset | TestKopioAsset,
  allowSeizeUnderflow = false,
) => {
  const [depositsBefore, debtBefore, liqAmount, updateData] = await Promise.all([
    hre.Diamond.getAccountCollateralAmount(user.address, collateral.address),
    hre.Diamond.getAccountDebtAmount(user.address, kopio.address),
    getLiqAmount(user, kopio, collateral),
    hre.updateData(),
  ])

  if (liqAmount.eq(0)) {
    return {
      collateralSeized: 0,
      debtRepaid: 0,
      tx: new Error('Not liquidatable'),
    }
  }
  const [minDebt, { pyth: pythPrice }] = await Promise.all([optimized.getMinDebtValue(), kopio.getPrice()])

  const minDebtAmount = minDebt.wadDiv(pythPrice)
  const liquidationAmount = liqAmount.lt(minDebtAmount) ? minDebtAmount : liqAmount
  const liquidatorBal = await kopio.balanceOf(hre.users.liquidator)
  if (liquidatorBal.lt(liquidationAmount)) {
    if (kopio.address === collateral.address) {
      await depositMockCollateral({
        user: hre.users.liquidator,
        asset: hre.extAssets.find(c => c.config.args.ticker === 'Collateral2')!,
        amount: toBig(100_000),
      })
    } else {
      await collateral.contract.setVariable('_balances', {
        [hre.users.liquidator.address]: toBig(100_000),
      })
      await depositCollateral({
        user: hre.users.liquidator,
        asset: collateral,
        amount: toBig(100_000),
      })
    }
    await mintKopio({
      user: hre.users.liquidator,
      asset: kopio,
      amount: liquidationAmount,
    })
  }

  const tx = await hre.Diamond.connect(hre.users.liquidator).liquidate({
    account: user.address,
    kopio: kopio.address,
    amount: liquidationAmount,
    collateral: collateral.address,
    prices: updateData,
  })

  const [depositsAfter, debtAfter, decimals] = await Promise.all([
    hre.Diamond.getAccountCollateralAmount(user.address, collateral.address),
    hre.Diamond.getAccountDebtAmount(user.address, kopio.address),
    collateral.contract.decimals(),
  ])
  return {
    collateralSeized: fromBig(depositsBefore.sub(depositsAfter), decimals),
    debtRepaid: fromBig(debtBefore.sub(debtAfter), 18),
    tx,
  }
}
