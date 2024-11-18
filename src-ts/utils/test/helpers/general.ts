import { type AssetArgs, type AssetConfig, OracleType } from '@/types'
import type { ERC20Mock } from '@/types/typechain'
import type { AssetStruct, TickerOraclesStruct } from '@/types/typechain/src/contracts/interfaces/KopioCore'
import { formatBytesString } from '@utils/values'
import { zeroAddress } from 'viem'
import { toBytes } from './oracle'

/* -------------------------------------------------------------------------- */
/*                                  GENERAL                                   */
/* -------------------------------------------------------------------------- */
export const updateTestAsset = async <T extends ERC20Mock | Kopio>(
  asset: TestAsset<T, 'mock'>,
  args: TestAssetUpdate,
) => {
  const { deployer } = await hre.ethers.getNamedSigners()
  const { newPrice, ...assetStruct } = args
  if (newPrice) {
    await asset.setPrice(newPrice)
    asset.config.args.price = newPrice
  }
  const newAssetConfig = { ...asset.config.assetStruct, ...assetStruct }
  await hre.Diamond.connect(deployer).updateAsset(asset.address, newAssetConfig)
  asset.config.assetStruct = newAssetConfig
  return asset
}
export const getAssetConfig = async (
  asset: { symbol: Function; decimals: Function },
  config: AssetArgs,
): Promise<AssetConfig> => {
  if (!config.kopioConfig && !config.collateralConfig && !config.scdpDepositConfig && !config.scdpKopioConfig)
    throw new Error('No config provided')
  const [decimals, symbol] = await Promise.all([asset.decimals(), asset.symbol()])

  const assetStruct: AssetStruct = {
    ticker: formatBytesString(config.ticker, 32),
    oracles: (config.oracleIds as any) ?? [OracleType.Pyth, OracleType.Chainlink],
    isCollateral: !!config.collateralConfig,
    isGlobalDepositable: !!config.scdpDepositConfig,
    isSwapMintable: !!config.scdpKopioConfig,
    isKopio: !!config.kopioConfig,
    factor: config.collateralConfig?.cFactor ?? 0,
    liqIncentive: config.collateralConfig?.liqIncentive ?? 0,
    mintLimit: config.kopioConfig?.mintLimit ?? 0,
    mintLimitSCDP: config.scdpKopioConfig?.mintLimitSCDP ?? 0,
    depositLimitSCDP: config.scdpDepositConfig?.depositLimitSCDP ?? 0,
    swapInFee: config.scdpKopioConfig?.swapInFee ?? 0,
    swapOutFee: config.scdpKopioConfig?.swapOutFee ?? 0,
    liqIncentiveSCDP: config.scdpKopioConfig?.liqIncentiveSCDP ?? 0,
    protocolFeeShareSCDP: config.scdpKopioConfig?.protocolFeeShareSCDP ?? 0,
    dFactor: config.kopioConfig?.dFactor ?? 0,
    closeFee: config.kopioConfig?.closeFee ?? 0,
    openFee: config.kopioConfig?.openFee ?? 0,
    share: config.kopioConfig?.share ?? zeroAddress,
    decimals: decimals,
    isGlobalCollateral: !!config.scdpDepositConfig || !!config.scdpKopioConfig,
    isCoverAsset: false,
  }

  if (assetStruct.isKopio) {
    if (assetStruct.share == zeroAddress || assetStruct.share == null) {
      throw new Error('Kopio share cannot be zero address')
    }
    if (assetStruct.dFactor === 0) {
      throw new Error('Kopio dFactor cannot be zero')
    }
  }

  if (assetStruct.isCollateral) {
    if (assetStruct.factor === 0) {
      throw new Error('Colalteral factor cannot be zero')
    }
    if (assetStruct.liqIncentive === 0) {
      throw new Error('Collateral liquidation incentive cannot be zero')
    }
  }

  if (assetStruct.isSwapMintable) {
    if (assetStruct.liqIncentiveSCDP === 0) {
      throw new Error('Kopio liquidation incentive cannot be zero')
    }
  }

  if (!config.feed) {
    throw new Error('No feed provided')
  }

  const feedConfig: TickerOraclesStruct = {
    oracleIds: assetStruct.oracles,
    pythId: toBytes(config.pyth.id),
    invertPyth: config.pyth.invert,
    isClosable: false,
    staleTimes: config.staleTimes ?? [10000, 86401],
    feeds: assetStruct.oracles[0] === OracleType.Pyth ? [zeroAddress, config.feed] : [config.feed, zeroAddress],
  }
  return { args: config, assetStruct, feedConfig, extendedInfo: { decimals, symbol } }
}
