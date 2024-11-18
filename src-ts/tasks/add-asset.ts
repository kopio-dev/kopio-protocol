import { getLogger } from '@utils/logging'
import { getShareMeta } from '@utils/strings'
import { getAssetConfig } from '@utils/test/helpers/general'
import { task, types } from 'hardhat/config'

import type { AssetArgs } from '@/types'
import type { ERC20Mock, ONE } from '@/types/typechain'
import { TestTickers } from '@utils/test/helpers/oracle'
import { zeroAddress } from 'viem'
import { TASK_ADD_ASSET } from './names'

type AddAssetArgs = {
  address: string
  assetConfig: AssetArgs
  log: boolean
}

const logger = getLogger(TASK_ADD_ASSET)
task(TASK_ADD_ASSET)
  .addParam('address', 'address of the asset', zeroAddress, types.string)
  .addParam('assetConfig', 'configuration for the asset', '', types.json)
  .setAction(async function (taskArgs: AddAssetArgs, hre) {
    const { address } = taskArgs
    if (!taskArgs.assetConfig?.feed) throw new Error('Asset config is empty')

    const config = taskArgs.assetConfig
    if (!config.feed || config.feed === zeroAddress) {
      throw new Error(`Invalid feed address: ${config.feed}, Asset: ${config.symbol}`)
    }
    if (address == zeroAddress) {
      throw new Error(`Invalid address: ${address}, Asset: ${config.symbol}`)
    }
    const isKopio = config.kopioConfig || config.scdpKopioConfig
    const isCollateral = config.collateralConfig
    const isSCDPDepositable = config.scdpDepositConfig
    const isONE = config.symbol === 'ONE'

    if (isONE && hre.ONE?.address != null) {
      throw new Error('Adding ONE but it exists')
    }

    if (!isKopio && !isCollateral && !isSCDPDepositable) {
      throw new Error(`Asset has no identity: ${config.symbol}`)
    }
    if (isKopio && hre.kopios.find(c => c.address === address)?.address) {
      throw new Error(`Adding an asset that is Kopio but it already exists: ${config.symbol}`)
    }

    if (isCollateral && hre.extAssets.find(c => c.address === address)?.address) {
      throw new Error(`Adding asset that is collateral but it already exists: ${config.symbol}`)
    }

    if (isKopio && config.kopioConfig?.dFactor === 0) {
      throw new Error(`Invalid dFactor for ${config.symbol}`)
    }
    if (isCollateral && config.collateralConfig?.cFactor === 0) {
      throw new Error(`Invalid cFactor for ${config.symbol}`)
    }
    const pythId = TestTickers[config.ticker as keyof typeof TestTickers]
    if (!pythId) throw new Error(`Pyth id not found for: ${config.symbol}`)

    const KopioCore = await hre.getContractOrFork('KopioCore')
    const Asset = isONE
      ? await hre.getContractOrFork('ONE')
      : isKopio
        ? await hre.getContractOrFork('Kopio', config.symbol)
        : await hre.getContractOrFork('ERC20Mock', config.symbol)

    const assetInfo = await KopioCore.getAsset(Asset.address)
    const exists = assetInfo.decimals != 0
    const asset: TestAsset<typeof Asset> = {
      ticker: config.ticker,
      address: Asset.address,
      isMocked: false,
      // @ts-expect-error
      config: {
        args: config,
      },
      balanceOf: acc => Asset.balanceOf(typeof acc === 'string' ? acc : acc.address),
      contract: Asset,
      assetInfo: () => KopioCore.getAsset(Asset.address),
      priceFeed: await hre.ethers.getContractAt('MockOracle', config.feed),
    }

    const { symbol: shareSymbol } = getShareMeta(config.symbol, config.name)
    if (exists) {
      logger.warn(`Asset ${config.symbol} already exists, skipping..`)
    } else {
      const share = isONE
        ? await hre.ethers.getContractAt('KopioShare', Asset.address)
        : await hre.getContractOrNull('KopioShare', shareSymbol)

      if (config.kopioConfig) {
        if (!share) {
          throw new Error(`Add asset failed because no share exist (${config.symbol})`)
        }
        config.kopioConfig!.share = share.address
        asset.share = share
        asset.isKopio = true
      }

      if (config.scdpKopioConfig) {
        if (!share) {
          throw new Error(`Add asset failed because no share exist (${config.symbol})`)
        }
        config.kopioConfig!.share = share.address
        asset.share = share
        asset.isKopio = true
      }

      logger.log(`Adding asset to protocol ${config.symbol}`)

      const parsedConfig = await getAssetConfig(Asset, config)

      asset.config.assetStruct = parsedConfig.assetStruct
      asset.config.feedConfig = parsedConfig.feedConfig
      asset.config.extendedInfo = parsedConfig.extendedInfo
      const tx = await KopioCore.addAsset(Asset.address, parsedConfig.assetStruct, parsedConfig.feedConfig)
      logger.success('Transaction hash: ', tx.hash)
      logger.success(`Succesfully added asset: ${config.symbol}`)
    }

    if (isONE) {
      hre.ONE = asset as TestAsset<ONE>
      return asset
    }
    if (asset.share != null) {
      hre.kopios.push(asset as TestAsset<Kopio, any>)
    } else if (asset.config.assetStruct.isCollateral) {
      hre.extAssets.push(asset as TestAsset<ERC20Mock, any>)
    }
    return asset
  })
