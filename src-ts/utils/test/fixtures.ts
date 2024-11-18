import type { SCDPKopioConfig } from '@/types'
import type { SmockCollateralReceiver, SmockCollateralReceiver__factory } from '@/types/typechain'
import type { KopioCore } from '@/types/typechain/src/contracts/interfaces/KopioCore'
import type { AllTokenSymbols } from '@config/hardhat/deploy'
import { type MockContract, smock } from '@defi-wonderland/smock'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import { createKopio } from '@scripts/create-kopio'
import { MaxUint128, toBig } from '@utils/values'
import type { Facet } from 'hardhat-deploy/dist/types'
import { zeroAddress } from 'viem'
import { addMockKopio, kopioLeverage, mintKopio } from './helpers/assets'
import { addMockExtAsset, depositCollateral } from './helpers/collaterals'

import {
  HUNDRED_USD,
  ONE_USD,
  TEN_USD,
  defaultCloseFee,
  defaultOpenFee,
  defaultSupplyLimit,
  testCollateralConfig,
  testKopioConfig,
} from './mocks'
import { Role } from './roles'

type SCDPFixtureParams = undefined

export type SCDPFixture = {
  reset: () => Promise<void>
  kopios: TestKopioAsset[]
  collaterals: TestExtAsset[]
  usersArr: SignerWithAddress[]
  Kopio: TestKopioAsset
  Kopio2: TestKopioAsset
  ONE: TestKopioAsset
  Collateral: TestExtAsset
  Collateral8Dec: TestExtAsset
  swapOneConfig: SCDPKopioConfig
  CollateralPrice: BigNumber
  KopioPrice: BigNumber
  Kopio2Price: BigNumber
  ONEPrice: BigNumber
  swapKopioConfig: SCDPKopioConfig
  swapper: SignerWithAddress
  depositor: SignerWithAddress
  depositor2: SignerWithAddress
  liquidator: SignerWithAddress
  KOPIO_ONE_ROUTE_FEE: number
  Swapper: typeof hre.Diamond
  Depositor: typeof hre.Diamond
  Depositor2: typeof hre.Diamond
  Liquidator: typeof hre.Diamond
}

export const scdpFixture = hre.deployments.createFixture<SCDPFixture, SCDPFixtureParams>(async hre => {
  const result = await hre.deployments.fixture('local')

  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }
  // preload for price updates
  await hre.users.deployer.sendTransaction({
    to: hre.Diamond.address,
    value: (1).ebn(18),
  })

  await time.increase(3610)

  const Collateral = hre.extAssets.find(c => c.config.args.symbol === testCollateralConfig.symbol)!
  const Coll8Dec = hre.extAssets.find(c => c.config.args.symbol === 'Coll8Dec')!

  await Collateral.update({
    isGlobalDepositable: true,
    depositLimitSCDP: MaxUint128,
    newPrice: TEN_USD,
  })
  await Coll8Dec.update({
    isGlobalDepositable: true,
    depositLimitSCDP: MaxUint128,
    factor: 0.8e4,
    newPrice: TEN_USD,
  })

  const Kopio = hre.kopios.find(k => k.config.args.symbol === testKopioConfig.symbol)!
  const Kopio2 = hre.kopios.find(k => k.config.args.symbol === 'Kopio2')!
  const swapKopioConfig = {
    swapInFee: 0.015e4,
    swapOutFee: 0.015e4,
    protocolFeeShareSCDP: 0.25e4,
    liqIncentiveSCDP: 1.05e4,
    mintLimitSCDP: defaultSupplyLimit,
  }

  const swapOneConfig = {
    swapInFee: 0.025e4,
    swapOutFee: 0.025e4,
    liqIncentiveSCDP: 1.05e4,
    protocolFeeShareSCDP: 0.25e4,
    mintLimitSCDP: defaultSupplyLimit,
  }
  const ONE = await addMockKopio({
    ticker: 'MockONE',
    price: ONE_USD,
    symbol: 'ONE',
    pyth: {
      id: 'MockONE',
      invert: false,
    },
    kopioConfig: {
      share: null,
      closeFee: 0.025e4,
      openFee: 0.025e4,
      dFactor: 1e4,
      mintLimit: defaultSupplyLimit,
    },
    collateralConfig: {
      cFactor: 1e4,
      liqIncentive: 1.1e4,
    },
    scdpKopioConfig: swapOneConfig,
    scdpDepositConfig: {
      depositLimitSCDP: MaxUint128,
    },
    marketOpen: true,
  })
  await Kopio.update({
    dFactor: 1.25e4,
    openFee: 0.01e4,
    closeFee: 0.01e4,
    isCollateral: true,
    factor: 1e4,
    liqIncentive: 1.1e4,
    isSwapMintable: true,
    newPrice: TEN_USD,
    ...swapKopioConfig,
  })
  await Kopio2.update({
    dFactor: 1e4,
    openFee: 0.015e4,
    closeFee: 0.015e4,
    isCollateral: true,
    factor: 1e4,
    liqIncentive: 1.1e4,
    isSwapMintable: true,
    newPrice: HUNDRED_USD,
    ...swapKopioConfig,
  })

  const kopios = [Kopio, Kopio2, ONE]
  const collaterals = [Collateral, Coll8Dec]

  const users = [hre.users.userTen, hre.users.userEleven, hre.users.userTwelve]

  await hre.Diamond.setGlobalIncome(ONE.address)
  for (const user of users) {
    await Promise.all([
      ...kopios.map(async asset =>
        asset.contract.setVariable('_allowances', {
          [user.address]: {
            [hre.Diamond.address]: hre.ethers.constants.MaxInt256,
          },
        }),
      ),
      ...collaterals.map(async asset =>
        asset.contract.setVariable('_allowances', {
          [user.address]: {
            [hre.Diamond.address]: hre.ethers.constants.MaxInt256,
          },
        }),
      ),
    ])
  }

  await hre.Diamond.setSwapRoutes([
    {
      assetIn: Kopio2.address,
      assetOut: Kopio.address,
      enabled: true,
    },
    {
      assetIn: ONE.address,
      assetOut: Kopio2.address,
      enabled: true,
    },
    {
      assetIn: Kopio.address,
      assetOut: ONE.address,
      enabled: true,
    },
  ])

  const reset = async () => {
    const depositAmount = 1000
    const depositAmount18Dec = toBig(depositAmount)
    const depositAmount8Dec = toBig(depositAmount, 8)
    await Promise.all([
      Collateral.setPrice(TEN_USD),
      Coll8Dec.setPrice(TEN_USD),
      Kopio.setPrice(TEN_USD),
      Kopio2.setPrice(HUNDRED_USD),
      ONE.setPrice(ONE_USD),
    ])

    for (const user of users) {
      await Collateral.setBalance(user, depositAmount18Dec, hre.Diamond.address)
      await Coll8Dec.setBalance(user, depositAmount8Dec, hre.Diamond.address)
    }
  }

  return {
    reset,
    CollateralPrice: TEN_USD.ebn(8),
    KopioPrice: TEN_USD.ebn(8),
    Kopio2Price: HUNDRED_USD.ebn(8),
    ONEPrice: ONE_USD.ebn(8),
    swapOneConfig,
    swapKopioConfig,
    Kopio: Kopio,
    Kopio2: Kopio2,
    ONE,
    KOPIO_ONE_ROUTE_FEE: swapOneConfig.swapOutFee + swapKopioConfig.swapInFee,
    Collateral: Collateral,
    Collateral8Dec: Coll8Dec,
    collaterals,
    kopios,
    usersArr: users,
    swapper: users[0],
    depositor: users[1],
    depositor2: users[2],
    liquidator: hre.users.liquidator,
    Swapper: hre.Diamond.connect(users[0]),
    Depositor: hre.Diamond.connect(users[1]),
    Depositor2: hre.Diamond.connect(users[2]),
    Liquidator: hre.Diamond.connect(hre.users.liquidator),
  }
})

const getReceiver = async (protocol: KopioCore, grantRole = true) => {
  const Receiver = await (await smock.mock<SmockCollateralReceiver__factory>('SmockCollateralReceiver')).deploy(
    protocol.address,
  )
  if (grantRole) {
    await protocol.grantRole(Role.MANAGER, Receiver.address)
  }
  return Receiver
}

export const diamondFixture = hre.deployments.createFixture<{ facets: Facet[] }, {}>(async hre => {
  const result = await hre.deployments.fixture('diamond-init')
  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }

  return {
    facets: result.Diamond?.facets?.length ? result.Diamond.facets : [],
  }
})

export const kopioFixture = hre.deployments.createFixture<
  Awaited<ReturnType<typeof createKopio>>,
  { name: string; symbol: AllTokenSymbols; underlyingToken?: string }
>(async (hre, opts) => {
  const result = await hre.deployments.fixture(['diamond-init', opts?.name!])
  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }
  if (!opts) throw new Error('Must supply options')
  return createKopio(
    opts?.symbol,
    opts?.name,
    18,
    opts.underlyingToken ?? zeroAddress,
    hre.users.treasury.address,
    0,
    0,
  )
})

export type DefaultFixture = {
  users: [SignerWithAddress, KopioCore][]
  collaterals: TestExtAsset[]
  kopios: TestKopioAsset[]
  Kopio: TestKopioAsset
  Collateral: TestExtAsset
  Collateral2: TestExtAsset
  Receiver: MockContract<SmockCollateralReceiver>
  depositAmount: BigNumber
  mintAmount: BigNumber
}

export const defaultFixture = hre.deployments.createFixture<DefaultFixture, {}>(async hre => {
  const result = await hre.deployments.fixture('local')
  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }
  // preload for price updates
  await hre.users.deployer.sendTransaction({
    to: hre.Diamond.address,
    value: (1).ebn(18),
  })

  await time.increase(3610)

  const depositAmount = toBig(1000)
  const mintAmount = toBig(100)
  const DefaultCollateral = hre.extAssets.find(c => c.config.args.ticker === testCollateralConfig.ticker)!
  const DefaultKopio = hre.kopios.find(k => k.config.args.ticker === testKopioConfig.ticker)!
  const Collateral2 = hre.extAssets.find(c => c.config.args.ticker === 'Collateral2')!

  const blankUser = hre.users.userOne
  const userWithDeposits = hre.users.userTwo
  const userWithMint = hre.users.userThree

  await DefaultCollateral.setBalance(userWithDeposits, depositAmount, hre.Diamond.address)
  await DefaultCollateral.setBalance(userWithMint, depositAmount, hre.Diamond.address)

  await depositCollateral({ user: userWithDeposits, asset: DefaultCollateral, amount: depositAmount })
  await depositCollateral({ user: userWithMint, asset: DefaultCollateral, amount: depositAmount })
  await mintKopio({ user: userWithMint, asset: DefaultKopio, amount: mintAmount })

  const Receiver = await getReceiver(hre.Diamond)

  return {
    users: [
      [blankUser, hre.Diamond.connect(blankUser)],
      [userWithDeposits, hre.Diamond.connect(userWithDeposits)],
      [userWithMint, hre.Diamond.connect(userWithMint)],
    ],
    collaterals: hre.extAssets,
    kopios: hre.kopios,
    Kopio: DefaultKopio,
    Collateral: DefaultCollateral,
    Collateral2,
    Receiver: Receiver.connect(userWithMint),
    depositAmount,
    mintAmount,
  }
})
export type AssetValuesFixture = {
  startingBalance: number
  user: SignerWithAddress
  Kopio: TestKopioAsset
  CollateralAsset: TestExtAsset
  CollateralAsset8Dec: TestExtAsset
  CollateralAsset21Dec: TestExtAsset
  oracleDecimals: number
}

export const assetValuesFixture = hre.deployments.createFixture<AssetValuesFixture, {}>(async hre => {
  const result = await hre.deployments.fixture('local')

  if (result.Diamond) hre.Diamond = await hre.getContractOrFork('KopioCore')

  await hre.users.deployer.sendTransaction({
    to: hre.Diamond.address,
    value: (1).ebn(18),
  })

  await time.increase(3610)
  const Kopio = hre.kopios.find(c => c.config.args.symbol === testKopioConfig.symbol)!
  await hre.Diamond.updateAsset(Kopio.address, {
    ...Kopio.config.assetStruct,
    openFee: 0.1e4,
    closeFee: 0.1e4,
    dFactor: 2e4,
  })

  const CollateralAsset = hre.extAssets.find(c => c.config.args.symbol === testCollateralConfig.symbol)!
  const Coll8Dec = hre.extAssets!.find(c => c.config.args.symbol === 'Coll8Dec')!

  const CollateralAsset21Dec = await addMockExtAsset({
    ticker: 'Coll21Dec',
    symbol: 'Coll21Dec',
    price: TEN_USD,
    pyth: {
      id: 'Coll21Dec',
      invert: false,
    },
    collateralConfig: {
      cFactor: 0.5e4,
      liqIncentive: 1.1e4,
    },
    decimals: 21, // more
  })
  await hre.Diamond.setCFactor(Coll8Dec.address, 0.5e4)
  await hre.Diamond.setCFactor(CollateralAsset.address, 0.5e4)

  const user = hre.users.userEight
  const startingBalance = 100
  await CollateralAsset.setBalance(user, toBig(startingBalance), hre.Diamond.address)
  await Coll8Dec.setBalance(user, toBig(startingBalance, 8), hre.Diamond.address)
  await CollateralAsset21Dec.setBalance(user, toBig(startingBalance, 21), hre.Diamond.address)

  return {
    oracleDecimals: await hre.Diamond.getOracleDecimals(),
    startingBalance,
    user,
    Kopio,
    CollateralAsset,
    CollateralAsset8Dec: Coll8Dec,
    CollateralAsset21Dec,
  }
})

export type DepositWithdrawFixture = {
  initialDeposits: BigNumber
  initialBalance: BigNumber
  Collateral: TestExtAsset
  Kopio: TestKopioAsset
  Collateral2: TestExtAsset
  KopioCollateral: TestKopioAsset
  depositor: SignerWithAddress
  withdrawer: SignerWithAddress
  user: SignerWithAddress
  User: KopioCore
  Depositor: KopioCore
  Withdrawer: KopioCore
}

export const depositWithdrawFixture = hre.deployments.createFixture<DepositWithdrawFixture, {}>(async hre => {
  const result = await hre.deployments.fixture('local')
  // preload for price updates
  await hre.users.deployer.sendTransaction({
    to: hre.Diamond.address,
    value: (1).ebn(18),
  })
  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }
  await time.increase(3610)

  const withdrawer = hre.users.userThree

  const DefaultCollateral = hre.extAssets.find(c => c.config.args.ticker === testCollateralConfig.ticker)!

  const DefaultKopio = hre.kopios.find(k => k.config.args.ticker === testKopioConfig.ticker)!
  const KopioCollateral = hre.kopios.find(k => k.config.args.ticker === 'Kopio3')!

  const initialDeposits = toBig(10000)
  const initialBalance = toBig(100000)
  await DefaultCollateral.setBalance(withdrawer, initialDeposits, hre.Diamond.address)
  await KopioCollateral.contract.setVariable('_allowances', {
    [withdrawer.address]: {
      [hre.Diamond.address]: hre.ethers.constants.MaxInt256,
    },
  })
  await DefaultCollateral.setBalance(hre.users.userOne, initialBalance, hre.Diamond.address)
  await DefaultCollateral.setBalance(hre.users.userTwo, initialBalance, hre.Diamond.address)
  await hre.Diamond.connect(withdrawer).depositCollateral(
    withdrawer.address,
    DefaultCollateral.address,
    initialDeposits,
  )

  return {
    initialDeposits,
    initialBalance,
    Collateral: DefaultCollateral,
    Kopio: DefaultKopio,
    Collateral2: hre.extAssets!.find(c => c.config.args.ticker === 'Collateral2')!,
    KopioCollateral,
    user: hre.users.userOne,
    depositor: hre.users.userTwo,
    withdrawer: hre.users.userThree,
    User: hre.Diamond.connect(hre.users.userOne),
    Depositor: hre.Diamond.connect(hre.users.userTwo),
    Withdrawer: hre.Diamond.connect(hre.users.userThree),
  }
})

export type MintRepayFixture = {
  reset: () => Promise<void>
  Collateral: TestExtAsset
  Kopio: TestKopioAsset
  Kopio2: TestKopioAsset
  Collateral2: TestExtAsset
  KopioCollateral: TestKopioAsset
  collaterals: TestExtAsset[]
  kopios: TestKopioAsset[]
  initialDeposits: BigNumber
  initialMintAmount: BigNumber
  user1: SignerWithAddress
  user2: SignerWithAddress
  User1: KopioCore
  User2: KopioCore
}

export const mintRepayFixture = hre.deployments.createFixture<MintRepayFixture, {}>(async hre => {
  const result = await hre.deployments.fixture('local')
  await hre.users.deployer.sendTransaction({
    to: hre.Diamond.address,
    value: (1).ebn(18),
  })
  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }
  await time.increase(3610)

  const DefaultCollateral = hre.extAssets.find(c => c.config.args.ticker === testCollateralConfig.ticker)!

  const DefaultKopio = hre.kopios.find(k => k.config.args.ticker === testKopioConfig.ticker)!
  const Kopio2 = hre.kopios.find(k => k.config.args.ticker === 'Kopio2')!
  const KopioCollateral = hre.kopios.find(k => k.config.args.ticker === 'Kopio3')!

  await DefaultKopio.contract.grantRole(Role.OPERATOR, hre.users.deployer.address)

  // Load account with collateral
  const initialDeposits = toBig(10000)
  const initialMintAmount = toBig(20)
  await DefaultCollateral.setBalance(hre.users.userOne, initialDeposits, hre.Diamond.address)
  await DefaultCollateral.setBalance(hre.users.userTwo, initialDeposits, hre.Diamond.address)

  // User deposits 10,000 collateral
  await depositCollateral({
    amount: initialDeposits,
    user: hre.users.userOne,
    asset: DefaultCollateral,
  })

  // Load userThree with KopioCore Assets
  await depositCollateral({
    user: hre.users.userTwo,
    asset: DefaultCollateral,
    amount: initialDeposits,
  })

  await mintKopio({ user: hre.users.userTwo, asset: DefaultKopio, amount: initialMintAmount })

  const reset = async () => {
    await DefaultKopio.setPrice(TEN_USD)
    await DefaultCollateral.setPrice(TEN_USD)
  }

  return {
    reset,
    collaterals: hre.extAssets,
    kopios: hre.kopios,
    initialDeposits,
    initialMintAmount,
    Collateral: DefaultCollateral,
    Kopio: DefaultKopio,
    Kopio2,
    Collateral2: hre.extAssets!.find(c => c.config.args.ticker === 'Collateral2')!,
    KopioCollateral,
    user1: hre.users.userOne,
    user2: hre.users.userTwo,
    User1: hre.Diamond.connect(hre.users.userOne),
    User2: hre.Diamond.connect(hre.users.userTwo),
  }
})

export type LiquidationFixture = {
  Collateral: TestExtAsset
  userOneMaxLiqPrecalc: BigNumber
  Collateral2: TestExtAsset
  Collateral8Dec: TestExtAsset
  Kopio: TestKopioAsset
  Kopio2: TestKopioAsset
  KopioCollateral: TestKopioAsset
  collaterals: TestExtAsset[]
  kopios: TestKopioAsset[]
  initialMintAmount: BigNumber
  initialDeposits: BigNumber
  reset: () => Promise<void>
  resetRebasing: () => Promise<void>
  Liquidator: KopioCore
  LiquidatorTwo: KopioCore
  User: KopioCore
  liquidator: SignerWithAddress
  liquidatorTwo: SignerWithAddress
  user1: SignerWithAddress
  user2: SignerWithAddress
  user3: SignerWithAddress
  user4: SignerWithAddress
  user5: SignerWithAddress
  kopioArgs: {
    price: number
    factor: BigNumberish
    mintLimit: BigNumberish
    closeFee: BigNumberish
    openFee: BigNumberish
  }
}

// Set up mock Kopio

export const liquidationsFixture = hre.deployments.createFixture<LiquidationFixture, {}>(async hre => {
  const result = await hre.deployments.fixture('local')
  // preload for price updates
  await hre.users.deployer.sendTransaction({
    to: hre.Diamond.address,
    value: (1).ebn(18),
  })
  if (result.Diamond) {
    hre.Diamond = await hre.getContractOrFork('KopioCore')
  }
  await time.increase(3610)
  const DefaultCollateral = hre.extAssets.find(c => c.config.args.ticker === testCollateralConfig.ticker)!
  const DefaultKopio = hre.kopios.find(c => c.config.args.ticker === testKopioConfig.ticker)!

  const Kopio2 = hre.kopios.find(c => c.config.args.ticker === 'Kopio2')!
  const KopioCollateral = hre.kopios!.find(k => k.config.args.ticker === 'Kopio3')!
  const Collateral2 = hre.extAssets.find(c => c.config.args.ticker === 'Collateral2')!
  const Collateral8Dec = hre.extAssets.find(c => c.config.args.ticker === 'Coll8Dec')!

  await DefaultKopio.contract.grantRole(Role.OPERATOR, hre.users.deployer.address)

  const initialDeposits = toBig(16.5)
  await DefaultCollateral.setBalance(hre.users.liquidator, toBig(100000000), hre.Diamond.address)
  await DefaultCollateral.setBalance(hre.users.userOne, initialDeposits, hre.Diamond.address)

  await depositCollateral({
    user: hre.users.userOne,
    amount: initialDeposits,
    asset: DefaultCollateral,
  })

  await depositCollateral({
    user: hre.users.liquidator,
    amount: toBig(100000000),
    asset: DefaultCollateral,
  })
  const initialMintAmount = toBig(10) // 10 * $11 = $110 in debt value
  await mintKopio({
    user: hre.users.userOne,
    amount: initialMintAmount,
    asset: DefaultKopio,
  })
  await mintKopio({
    user: hre.users.liquidator,
    amount: initialMintAmount.mul(1000),
    asset: DefaultKopio,
  })
  await DefaultKopio.setPrice(11)
  await DefaultCollateral.setPrice(7.5)
  const userOneMaxLiqPrecalc = (
    await hre.Diamond.getMaxLiqValue(hre.users.userOne.address, DefaultKopio.address, DefaultCollateral.address)
  ).repayValue

  await DefaultCollateral.setPrice(TEN_USD)

  const reset = async () => {
    await Promise.all([
      DefaultKopio.setPrice(11),
      Kopio2.setPrice(TEN_USD),
      DefaultCollateral.setPrice(testCollateralConfig.price!),
      Collateral2.setPrice(TEN_USD),
      Collateral8Dec.setPrice(TEN_USD),
      hre.Diamond.setCFactor(DefaultCollateral.address, 1e4),
      hre.Diamond.setDFactor(KopioCollateral.address, 1e4),
    ])
  }

  /* -------------------------------------------------------------------------- */
  /*                               Rebasing setup                               */
  /* -------------------------------------------------------------------------- */

  const collateralPriceRebasing = TEN_USD
  const kopioPriceRebasing = ONE_USD
  const thousand = toBig(1000) // $10k
  const rebasingAmounts = {
    liquidatorDeposits: thousand,
    userDeposits: thousand,
  }
  // liquidator
  await DefaultCollateral.setBalance(hre.users.userSeven, rebasingAmounts.liquidatorDeposits, hre.Diamond.address)
  await depositCollateral({
    user: hre.users.userSeven,
    asset: DefaultCollateral,
    amount: rebasingAmounts.liquidatorDeposits,
  })

  // another user
  await DefaultCollateral.setBalance(hre.users.userFour, rebasingAmounts.liquidatorDeposits, hre.Diamond.address)
  await depositCollateral({
    user: hre.users.userFour,
    asset: DefaultCollateral,
    amount: rebasingAmounts.liquidatorDeposits,
  })

  await DefaultKopio.setPrice(kopioPriceRebasing)
  await mintKopio({
    user: hre.users.userFour,
    asset: DefaultKopio,
    amount: toBig(6666.66666),
  })

  // another user
  await DefaultCollateral.setBalance(hre.users.userNine, rebasingAmounts.liquidatorDeposits, hre.Diamond.address)
  await depositCollateral({
    user: hre.users.userNine,
    asset: DefaultCollateral,
    amount: rebasingAmounts.liquidatorDeposits,
  })

  await DefaultKopio.setPrice(kopioPriceRebasing)
  await mintKopio({
    user: hre.users.userNine,
    asset: DefaultKopio,
    amount: toBig(6666.66666),
  })

  await DefaultKopio.setPrice(11)

  // another user
  await kopioLeverage(hre.users.userThree, KopioCollateral, DefaultCollateral, rebasingAmounts.userDeposits)
  await kopioLeverage(hre.users.userThree, KopioCollateral, DefaultCollateral, rebasingAmounts.userDeposits)

  const resetRebasing = async () => {
    await DefaultCollateral.setPrice(collateralPriceRebasing)
    await DefaultKopio.setPrice(kopioPriceRebasing)
  }

  /* --------------------------------- Values --------------------------------- */
  return {
    resetRebasing,
    reset,
    userOneMaxLiqPrecalc,
    collaterals: hre.extAssets,
    kopios: hre.kopios,
    initialDeposits,
    initialMintAmount,
    Collateral: DefaultCollateral,
    Kopio: DefaultKopio,
    Collateral2,
    Collateral8Dec,
    Kopio2: Kopio2,
    KopioCollateral,
    Liquidator: hre.Diamond.connect(hre.users.liquidator),
    LiquidatorTwo: hre.Diamond.connect(hre.users.userFive),
    User: hre.Diamond.connect(hre.users.userOne),
    liquidator: hre.users.liquidator,
    liquidatorTwo: hre.users.userFive,
    user1: hre.users.userOne,
    user2: hre.users.userTwo,
    user3: hre.users.userThree,
    user4: hre.users.userFour,
    user5: hre.users.userNine, // obviously not user5
    kopioArgs: {
      price: 11, // $11
      factor: 1e4,
      mintLimit: MaxUint128,
      closeFee: defaultCloseFee,
      openFee: defaultOpenFee,
    },
  }
})
