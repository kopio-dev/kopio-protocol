import { TASK_DEPLOY_ONE, TASK_DEPLOY_VAULT } from '@tasks'
import { getLogger } from '@utils/logging'
import type { DeployFunction } from 'hardhat-deploy/dist/types'

const logger = getLogger('create-ONE')

const deploy: DeployFunction = async hre => {
  try {
    await hre.run(TASK_DEPLOY_VAULT, { withMockAsset: true })
    const Vault = await hre.getContractOrFork('Vault', 'vONE')
    logger.success(`Deployed vONE @ ${Vault.address}`)
    await hre.run(TASK_DEPLOY_ONE)
  } catch (e) {
    console.log(e)
  }
}

deploy.skip = async hre => {
  if ((await hre.deployments.getOrNull('ONE')) != null) {
    logger.log('Skip: Create ONE, already created.')
    return true
  }
  return false
}

deploy.tags = ['all', 'local', 'tokens', 'ONE']
deploy.dependencies = ['facets', 'core']

export default deploy
