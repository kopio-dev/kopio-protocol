import { testnetConfigs } from '@config/hardhat/deploy/arbitrumSepolia'
import { createKopio } from '@scripts/create-kopio'
import { getLogger } from '@utils/logging'
import type { DeployFunction } from 'hardhat-deploy/dist/types'

const logger = getLogger('Create Kopio')

const deploy: DeployFunction = async function (hre) {
  const assets = testnetConfigs[hre.network.name].assets.filter(a => !!a.kopioConfig || !!a.scdpKopioConfig)

  for (const kopio of assets) {
    if (kopio.symbol === 'ONE') {
      logger.warn(`Skip: ${kopio.symbol}`)
      continue
    }
    const isDeployed = await hre.deployments.getOrNull(kopio.symbol)
    if (isDeployed != null) continue
    // Deploy the asset
    if (!kopio.kopioConfig?.underlyingAddr)
      throw new Error(`Underlying address should be zero address if it does not exist (${kopio.symbol})`)

    logger.log(`Create: ${kopio.name} (${kopio.symbol})`)
    await createKopio(
      kopio.symbol,
      kopio.name ? kopio.name : kopio.symbol,
      18,
      kopio.kopioConfig.underlyingAddr,
      hre.users.treasury.address,
      0,
      0,
    )
    logger.log(`Success: ${kopio.name}.`)
  }

  logger.success('Done.')
}

deploy.skip = async hre => {
  const logger = getLogger('deploy-tokens')
  const kopios = testnetConfigs[hre.network.name].assets.filter(a => !!a.kopioConfig || !!a.scdpKopioConfig)
  if (!kopios.length) {
    logger.log('Skip: No kopios configured.')
    return true
  }
  if (await hre.deployments.getOrNull(kopios[kopios.length - 1].symbol)) {
    logger.log('Skip: Create kopios, already created.')
    return true
  }
  return false
}

deploy.tags = ['local', 'all', 'tokens', 'kopios']
deploy.dependencies = ['core']

export default deploy
