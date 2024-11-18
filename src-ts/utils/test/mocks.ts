import { type AssetArgs, OracleType } from '@/types'
import { toBig } from '@utils/values'
import { maxUint256 } from 'viem'

export type InputArgs = {
  user: SignerWithAddress
  asset: TestAsset<any, any>
  amount: BigNumber
}

export type InputArgsSimple = Omit<InputArgs, 'asset'> & {
  asset: { address: string }
}

export const HUNDRED_USD = 100
export const TEN_USD = 10
export const ONE_USD = 1
export const defaultOracleDecimals = 8

export const defaultDecimals = 18

export const defaultDepositAmount = toBig(10, defaultDecimals)
export const defaultMintAmount = toBig(100, defaultDecimals)

export const defaultSupplyLimit = maxUint256
export const defaultCloseFee = 0.02e4 // 2%
export const defaultOpenFee = 0 // 0%

export const testKopioConfig: AssetArgs = {
  ticker: 'Kopio',
  name: 'Kopio',
  symbol: 'Kopio',
  marketOpen: true,
  price: TEN_USD,
  pyth: {
    id: 'Kopio',
    invert: false,
  },
  staleTimes: [10000, 86401],
  kopioConfig: {
    shareSymbol: 'aKopio',
    closeFee: defaultCloseFee,
    openFee: defaultOpenFee,
    dFactor: 1e4,
    mintLimit: defaultSupplyLimit,
    share: null,
  },
  oracleIds: [OracleType.Pyth, OracleType.Chainlink] as [OracleType, OracleType],
}

export const testCollateralConfig: AssetArgs = {
  ticker: 'Collateral',
  name: 'Collateral',
  symbol: 'Collateral',
  price: TEN_USD,
  marketOpen: true,
  pyth: {
    id: 'Collateral',
    invert: false,
  },
  staleTimes: [10000, 86401],
  collateralConfig: {
    cFactor: 1e4,
    liqIncentive: 1.1e4,
  },
  decimals: defaultDecimals,
  oracleIds: [OracleType.Pyth, OracleType.Chainlink] as [OracleType, OracleType],
}
export const testCommonParams = (feeRecipient: string) => ({
  minDebtValue: toBig(20, 8),
  feeRecipient: feeRecipient,
  maxPriceDeviationPct: 0.02e4,
})
export const testICDPParams = (feeRecipient: string) => ({
  minCollateralRatio: 1.8e4,
  liquidationThreshold: 1.3e4,
  maxLiquidationRatio: 1.32e4,
})

export default {
  mintLimit: defaultSupplyLimit,
  closeFee: defaultCloseFee,
  openFee: defaultOpenFee,
  mintAmount: defaultMintAmount,
  depositAmount: defaultDepositAmount,
  testCollateralConfig,
  testKopioConfig,
  oracle: {
    price: TEN_USD,
    decimals: defaultOracleDecimals,
  },
  testCommonParams,
  testICDPParams,
}
