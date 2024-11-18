import type { AssetConfig, ContractTypes, OracleType } from '@/types'
import type { FakeContract, MockContract } from '@defi-wonderland/smock'
import type {
  getBalanceCollateralFunc,
  getKopioBalanceFunc,
  setBalanceCollateralFunc,
  setKopioBalanceFunc,
} from '@utils/test/helpers/smock'
import type { BytesLike } from 'ethers'
import type { DeployResult, Deployment } from 'hardhat-deploy/dist/types'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type * as Contracts from './typechain'
import type { MockOracle } from './typechain'
import type { AssetStruct } from './typechain/src/contracts/interfaces/KopioCore'
import { PromiseOrValue } from './typechain/common'

declare global {
  const hre: HardhatRuntimeEnvironment

  export type TC = ContractTypes
  type TestExtAsset = TestAsset<Contracts.ERC20Mock, 'mock'>
  type TestKopioAsset = TestAsset<Kopio, 'mock'>
  type TestAssetUpdate = Partial<AssetStruct> & { newPrice?: number }
  type TestAsset<C extends Contracts.ERC20Mock | Kopio | Contracts.ONE, T extends 'mock' | undefined = undefined> = {
    ticker: string
    address: string
    isKopio?: boolean
    isCollateral?: boolean
    initialPrice: number
    pythId: PromiseOrValue<BytesLike>
    isMocked?: boolean
    contract: T extends 'mock' ? MockContract<C> : C
    config: AssetConfig
    assetInfo: () => Promise<AssetStruct>
    share: C extends Kopio ? (T extends 'mock' ? MockContract<Contracts.KopioShare> : Contracts.KopioShare) : null
    priceFeed: T extends 'mock' ? FakeContract<MockOracle> : MockOracle
    setBalance: T extends Kopio ? ReturnType<typeof setKopioBalanceFunc> : ReturnType<typeof setBalanceCollateralFunc>
    errorId: [string, string]
    balanceOf: T extends Kopio ? ReturnType<typeof getKopioBalanceFunc> : ReturnType<typeof getBalanceCollateralFunc>
    setPrice: (price: number) => Promise<void>
    setOracleOrder: (order: [OracleType, OracleType]) => Promise<any>
    getPrice: () => Promise<{ push: BigNumber; pyth: BigNumber }>
    update: (update: TestAssetUpdate) => Promise<TestAsset<C, T>>
  }

  export type TestTokenSymbols =
    | 'kSYMBOL'
    | 'USDC'
    | 'MockONE'
    | 'TSLA'
    | 'Collateral'
    | 'Coll8Dec'
    | 'Coll18Dec'
    | 'Coll21Dec'
    | 'Collateral2'
    | 'Collateral3'
    | 'Collateral4'
    | 'Kopio'
    | 'Kopio2'
    | 'Kopio3'
    | 'Kopio4'
    | 'Kopio5'
  type GnosisSafeL2 = any

  type Kopio = TC['Kopio']
  type ERC20Upgradeable = TC['ERC20Upgradeable']
  type BigNumberish = import('ethers').BigNumberish
  type BigNumber = import('ethers').BigNumber
  /* -------------------------------------------------------------------------- */
  /*                               Signers / Users                              */
  /* -------------------------------------------------------------------------- */
  type SignerWithAddress = import('@nomiclabs/hardhat-ethers/signers').SignerWithAddress

  /* -------------------------------------------------------------------------- */
  /*                                 Deployments                                */
  /* -------------------------------------------------------------------------- */

  // type DeployResultWithSignaturesUnknown<C extends Contract> = readonly [C, string[], DeployResult];
  type DeployResultWithSignatures<T> = readonly [T, string[], DeployResult]
  type ProxyDeployResult<T> = readonly [T, Deployment]

  type DiamondCutInitializer = [string, BytesLike]
}
