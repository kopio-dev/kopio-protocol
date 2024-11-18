import type { AssetArgs } from '@/types'
import { KopioShare, type KopioShare__factory, type Kopio__factory } from '@/types/typechain'
import { MockContract, smock } from '@defi-wonderland/smock'
import { getStorageAt, setStorageAt } from '@nomicfoundation/hardhat-network-helpers'
import { getShareMeta } from '@utils/strings'
import { toBig } from '@utils/values'
import { Hex, padHex, zeroAddress } from 'viem'
import { type InputArgsSimple, defaultCloseFee, defaultSupplyLimit, testKopioConfig } from '../mocks'
import { Role } from '../roles'
import { getAssetConfig, updateTestAsset } from './general'
import optimized from './optimizations'
import { createOracles, getPythPrice, updatePrices } from './oracle'
import { getKopioBalanceFunc, setKopioBalanceFunc } from './smock'

export const getDebtIndexAdjustedBalance = async (user: SignerWithAddress, asset: TestAsset<Kopio, any>) => {
  const balance = await asset.contract.balanceOf(user.address)
  return [balance, balance]
}

async function deployUninitialized(args: AssetArgs, deployer: SignerWithAddress) {
  const { name, symbol, price, marketOpen } = args
  const [kopioFactory, shareFactory] = await Promise.all([
    smock.mock<Kopio__factory>('Kopio', deployer),
    smock.mock<KopioShare__factory>('KopioShare', deployer),
  ])
  const { symbol: shareSymbol, name: shareName } = getShareMeta(symbol, name)
  const kopio = await kopioFactory.deploy()
  const share = await shareFactory.deploy(kopio.address)

  await Promise.all([
    setStorageAt(kopio.address, '0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00', 0),
    setStorageAt(share.address, '0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00', 0),
  ])

  await kopio.initialize(
    name || symbol,
    symbol,
    deployer.address,
    hre.Diamond.address,
    zeroAddress,
    hre.users.treasury.address,
    0,
    0,
  )
  await share.initialize(shareName, shareSymbol, deployer.address)

  return { kopio, share, fakeFeed: await createOracles(hre, args.pyth.id, price, marketOpen) }
}

export const addMockKopio = async (args = testKopioConfig): Promise<TestKopioAsset> => {
  if (hre.kopios.find(c => c.config.args.symbol === args.symbol)) {
    throw new Error(`Asset with symbol ${args.symbol} already exists`)
  }
  const deployer = hre.users.deployer
  const { kopio, share, fakeFeed } = await deployUninitialized(args, deployer)

  const [config] = await Promise.all([
    getAssetConfig(kopio, {
      ...args,
      feed: fakeFeed.address,
      kopioConfig: { ...args.kopioConfig!, share: share.address },
    }),
  ])

  // Add the asset to the protocol
  await Promise.all([
    hre.Diamond.connect(deployer).addAsset(kopio.address, config.assetStruct, config.feedConfig),
    kopio.grantRole(Role.OPERATOR, share.address),
  ])

  const asset: TestKopioAsset = {
    ticker: args.ticker,
    isKopio: true,
    isCollateral: !!args.collateralConfig,
    address: kopio.address,
    initialPrice: args.price!,
    assetInfo: () => hre.Diamond.getAsset(kopio.address),
    config,
    contract: kopio,
    priceFeed: fakeFeed,
    pythId: config.feedConfig.pythId,
    share,
    errorId: [args.symbol, kopio.address],
    setPrice: price => updatePrices(hre, fakeFeed, price, config.feedConfig.pythId.toString()),
    setBalance: setKopioBalanceFunc(kopio, share),
    balanceOf: getKopioBalanceFunc(kopio),
    setOracleOrder: order => hre.Diamond.setOracleTypes(kopio.address, order),
    getPrice: async () => ({
      push: (await fakeFeed.latestRoundData())[1],
      pyth: getPythPrice(config.feedConfig.pythId.toString()),
    }),
    update: update => updateTestAsset(asset, update),
  }

  const found = hre.kopios.findIndex(c => c.address === asset.address)
  if (found === -1) {
    hre.kopios.push(asset)
  } else {
    hre.kopios = hre.kopios.map(c => (c.address === asset.address ? asset : c))
  }
  return asset
}

export const mintKopio = async (args: InputArgsSimple) => {
  const convert = typeof args.amount === 'string' || typeof args.amount === 'number'
  const { user, asset, amount } = args
  return hre.Diamond.connect(user).mintKopio(
    {
      account: user.address,
      kopio: asset.address,
      amount: convert ? toBig(+amount) : amount,
      receiver: user.address,
    },
    hre.updateData(),
  )
}

export const burnKopio = async (args: InputArgsSimple) => {
  const convert = typeof args.amount === 'string' || typeof args.amount === 'number'
  const { user, asset, amount } = args

  return hre.Diamond.connect(user).burnKopio(
    {
      account: user.address,
      kopio: asset.address,
      amount: convert ? toBig(+amount) : amount,
      repayee: user.address,
    },
    hre.updateData(),
  )
}

export const kopioLeverage = async (
  user: SignerWithAddress,
  kopio: TestAsset<Kopio, 'mock'>,
  collateralToUse: TestAsset<any, 'mock'>,
  amount: BigNumber,
) => {
  const [kopioValueBig, mcrBig, collateralValue, collateralToUseInfo, kopioInfo, updateData, prices] =
    await Promise.all([
      hre.Diamond.getValue(kopio.address, amount),
      optimized.getMCR(),
      hre.Diamond.getValue(collateralToUse.address, toBig(1)),
      hre.Diamond.getAsset(collateralToUse.address),
      hre.Diamond.getAsset(kopio.address),
      hre.updateData(),
      collateralToUse.getPrice(),
    ])

  await kopio.contract.setVariable('_allowances', {
    [user.address]: {
      [hre.Diamond.address]: hre.ethers.constants.MaxInt256,
    },
  })

  const collateralValueRequired = kopioValueBig.percentMul(mcrBig)

  const price = collateralValue.num(8)
  const collateralAmount = collateralValueRequired.wadDiv(prices.pyth)

  await collateralToUse.setBalance(user, collateralAmount, hre.Diamond.address)

  const addPromises: Promise<any>[] = []
  if (!collateralToUseInfo.isCollateral) {
    const config = { ...collateralToUseInfo, isCollateral: true, factor: 1e4, liqIncentive: 1.1e4 }
    addPromises.push(hre.Diamond.updateAsset(collateralToUse.address, config))
  }
  if (!kopioInfo.isKopio) {
    const config = {
      ...kopioInfo,
      isKopio: true,
      dFactor: 1e4,
      mintLimit: defaultSupplyLimit,
      share: kopio.share.address,
      closeFee: defaultCloseFee,
      openFee: 0,
    }
    addPromises.push(hre.Diamond.updateAsset(kopio.address, config))
  }
  if (!kopioInfo.isCollateral) {
    const config = { ...kopioInfo, isCollateral: true, factor: 1e4, liqIncentive: 1.1e4 }
    addPromises.push(hre.Diamond.updateAsset(kopio.address, config))
  }
  await Promise.all(addPromises)
  const User = hre.Diamond.connect(user)
  await User.depositCollateral(user.address, collateralToUse.address, collateralAmount)
  await User.mintKopio({ account: user.address, kopio: kopio.address, amount, receiver: user.address }, updateData)
  await User.depositCollateral(user.address, kopio.address, amount)

  // Deposit kopio and withdraw other collateral to bare minimum of within healthy range

  const accountMinCollateralRequired = await hre.Diamond.getAccountMinCollateralAtRatio(
    user.address,
    optimized.getMCR(),
  )
  const accountCollateral = await hre.Diamond.getAccountTotalCollateralValue(user.address)

  const withdrawAmount = accountCollateral.sub(accountMinCollateralRequired).num(8) / price - 0.1
  const amountToWithdraw = withdrawAmount.ebn()

  if (amountToWithdraw.gt(0)) {
    await User.withdrawCollateral(
      {
        account: user.address,
        asset: collateralToUse.address,
        amount: amountToWithdraw,
        receiver: user.address,
      },
      updateData,
    )

    // "burn" collateral not needed
    await collateralToUse.setBalance(user, toBig(0))
    // await collateralToUse.contract.connect(user).transfer(hre.ethers.constants.AddressZero, amountToWithdraw);
  }
}
