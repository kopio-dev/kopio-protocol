import { getDeploymentUsers } from '@config/hardhat/deploy'
import { getLogger } from '@utils/logging'
import { testKopioConfig } from '@utils/test/mocks'
import { Role } from '@utils/test/roles'
import { MaxUint128, toBig } from '@utils/values'
import { task } from 'hardhat/config'
import type { TaskArguments } from 'hardhat/types'
import { TASK_DEPLOY_ONE } from './names'

const logger = getLogger(TASK_DEPLOY_ONE)

task(TASK_DEPLOY_ONE).setAction(async function (_taskArgs: TaskArguments, hre) {
  logger.log(`Deploying ONE`)
  const { deployer } = await hre.getNamedAccounts()
  if (!hre.DeploymentFactory) {
    ;[hre.DeploymentFactory] = await hre.deploy('ProxyFactory', {
      args: [deployer],
    })
  }
  const VaultDeployment = await hre.deployments.getOrNull('vONE')
  if (!VaultDeployment?.address) {
    if (hre.network.name === 'hardhat') {
      await hre.run('deploy:vault', { withMockAsset: true })
    } else {
      throw new Error('Vault is not deployed')
    }
  }
  const Vault = await hre.getContractOrFork('Vault', 'vONE')
  const { multisig } = await getDeploymentUsers(hre)
  const Diamond = await hre.getContractOrFork('Diamond')
  const args = {
    name: 'ONE',
    symbol: 'ONE',
    decimals: 18,
    admin: multisig,
    operator: Diamond.address,
  }

  const ONE = await hre.deployProxy('ONE', {
    initializer: 'initialize',
    initializerArgs: [args.name, args.symbol, args.admin, args.operator, Vault.address],
    type: 'create3',
    salt: 'ONE',
  })

  const hasRole = await ONE.hasRole(Role.OPERATOR, args.operator)
  const hasRoleAdmin = await ONE.hasRole(Role.ADMIN, args.admin)

  if (!hasRoleAdmin) {
    throw new Error(`Multisig is missing Role.ADMIN`)
  }
  if (!hasRole) {
    throw new Error(`Diamond is missing Role.OPERATOR`)
  }
  logger.success(`ONE succesfully deployed @ ${ONE.address}`)
  // Add to runtime for tests and further scripts

  const asset = {
    address: ONE.address,
    contract: ONE,
    config: {
      args: {
        name: 'ONE',
        price: 1,
        factor: 1e4,
        mintLimit: MaxUint128,
        marketOpen: true,
        kopioConfig: testKopioConfig.kopioConfig,
      },
    },
    initialPrice: 1,
    errorId: ['ONE', ONE.address],
    assetInfo: () => hre.Diamond.getAsset(ONE.address),
    getPrice: async () => toBig(1, 8),
    priceFeed: {} as any,
  }

  return asset
})
