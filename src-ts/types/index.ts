import type { AllTokenSymbols } from '@config/hardhat/deploy'
import type { AssetConfigExtended } from '@config/hardhat/deploy/arbitrumSepolia'
import type { BigNumber, Overrides } from 'ethers'
import type { Address } from 'hardhat-deploy/dist/types'
import type * as Contracts from './typechain'
import type {
  AssetStruct,
  CommonInitializerStruct,
  TickerOraclesStruct,
  ICDPInitializerStruct,
  SCDPInitializerStruct,
} from './typechain/src/contracts/interfaces/KopioCore'
import type { AllTickers } from '@utils/test/helpers/oracle'

export type ContractTypes = GetContractTypes<typeof Contracts>
export type ContractNames = keyof ContractTypes

export type NetworkConfig = {
  [network: string]: {
    commonInitializer: Omit<CommonInitializerStruct, 'feeRecipient' | 'admin' | 'council' | 'treasury'>
    icdpInitializer: ICDPInitializerStruct
    scdpInitializer: SCDPInitializerStruct
    assets: AssetConfigExtended[]
    gnosisSafeDeployments?: GnosisSafeDeployment[]
  }
}

export enum OracleType {
  Empty,
  Redstone,
  Chainlink,
  API3,
  Vault,
  Pyth,
}

export enum Action {
  DEPOSIT = 0,
  WITHDRAW = 1,
  REPAY = 2,
  BORROW = 3,
  LIQUIDATION = 4,
  SCDP_DEPOSIT = 5,
  SCDP_SWAP = 6,
  SCDP_WITHDRAW = 7,
  SCDP_REPAY = 8,
  SCDP_LIQUIDATION = 9,
}

export enum ICDPFee {
  OPEN = 0,
  CLOSE = 1,
}

export type SCDPDepositAssetConfig = {
  depositLimitSCDP: BigNumberish
}

type ExtendedInfo = {
  decimals: number
  symbol: string
}

export type AssetConfig = {
  args: AssetArgs
  assetStruct: AssetStruct
  feedConfig: TickerOraclesStruct
  extendedInfo: ExtendedInfo
}
export type AssetArgs = {
  ticker: AllTickers
  getPrice?: () => Promise<BigNumber>
  getMarketStatus?: () => Promise<boolean>
  symbol: AllTokenSymbols
  name?: string
  price?: number
  staleTimes?: [number, number]
  pyth: {
    id: string | null
    invert: boolean
  }
  marketOpen?: boolean
  decimals?: number
  feed?: string
  oracleIds?: [OracleType, OracleType] | readonly [OracleType, OracleType]
  collateralConfig?: CollateralConfig
  kopioConfig?: KopioConfig
  scdpKopioConfig?: SCDPKopioConfig
  scdpDepositConfig?: SCDPDepositAssetConfig
}

export type KopioConfig = {
  share: string | null
  shareSymbol?: string
  underlyingAddr?: string
  dFactor: BigNumberish
  mintLimit: BigNumberish
  closeFee: BigNumberish
  openFee: BigNumberish
}

export type SCDPKopioConfig = {
  swapInFee: BigNumberish
  swapOutFee: BigNumberish
  liqIncentiveSCDP: BigNumberish
  protocolFeeShareSCDP: BigNumberish
  mintLimitSCDP: BigNumberish
}

export type CollateralConfig = {
  cFactor: BigNumberish
  liqIncentive: BigNumberish
}
export type ICDPInitializer = {
  name: 'ICDPConfigFacet'
  args: ICDPInitializerStruct
}
export type SCDPInitializer = {
  name: 'SCDPConfigFacet'
  args: SCDPInitializerStruct
}
export type CommonInitializer = {
  name: 'CommonConfigFacet'
  args: CommonInitializerStruct
}

export type GnosisSafeDeployment = {
  defaultAddress: Address
  released: boolean
  contractName: string
  version: string
  networkAddresses: {
    opgoerli: string
  }
  abi: any
}

/* -------------------------------------------------------------------------- */
/*                                 TYPE UTILS                                 */
/* -------------------------------------------------------------------------- */
export type FuncNames<T extends ContractNames> = keyof TC[T]['functions'] | undefined

export type FuncArgs<F extends FuncNames<T>, T extends ContractNames> = F extends keyof TC[T]['functions']
  ? TC[T]['functions'][F] extends (...args: infer Args) => any
    ? Args extends readonly [...infer Args2, overrides?: Overrides | undefined]
      ? Args2 extends []
        ? never
        : readonly [...Args2]
      : never
    : never
  : never
export type Or<T extends readonly unknown[]> = T extends readonly [infer Head, ...infer Tail]
  ? Head extends true
    ? true
    : Or<Tail>
  : false
export type ValueOf<T> = T[keyof T]

export type IsUndefined<T> = [undefined] extends [T] ? true : false
export type MaybeExcludeEmpty<T, TMaybeExclude extends boolean> = TMaybeExclude extends true
  ? Exclude<T, [] | null | undefined>
  : T

export type MaybeRequired<T, TRequired extends boolean> = TRequired extends true ? Required<T> : T
export type MaybeUndefined<T, TUndefinedish extends boolean> = TUndefinedish extends true ? T | undefined : T
export type Split<S extends string, D extends string> = string extends S
  ? string[]
  : S extends ''
    ? []
    : S extends `${infer T}${D}${infer U}`
      ? [T, ...Split<U, D>]
      : [S]
export type Prettify<T> = {
  [K in keyof T]: T[K]
} & {}
export type ExcludeType<T, E> = {
  [K in keyof T]: T[K] extends E ? K : never
}[keyof T]

export type Excludes =
  | 'AccessControlEnumerableUpgradeable'
  | 'AccessControlUpgradeable'
  | 'FallbackManager'
  | 'BaseGuard'
  | 'Guard'
  | 'GuardManager'
  | 'ModuleManager'
  | 'OwnerManager'
  | 'EtherPaymentFallback'
  | 'StorageAccessible'

type KeyValue<T = unknown> = {
  [key: string]: T
}
export type FactoryName<T extends KeyValue> = Exclude<keyof T, 'factories'>
export type MinEthersFactoryExt<C> = {
  connect(address: string, signerOrProvider: any): C
}
export type InferContractType<Factory> = Factory extends MinEthersFactoryExt<infer C> ? C : unknown

export type GetContractTypes<T extends KeyValue> = {
  [K in FactoryName<T> as `${Split<K extends string ? K : never, '__factory'>[0]}`]: InferContractType<T[K]>
}
