import type { VaultAssetStruct } from '@/types/typechain/src/contracts/core/vault/Vault'
import { MAX_UINT_AMOUNT, MaxUint128, toBig } from '@utils/values'
import { task, types } from 'hardhat/config'
import { TASK_DEPLOY_VAULT } from './names'

type VaultTaskArgs = {
  mockAsset: {
    deploy: boolean
    mintAmount: BigNumber
  }
}

task(TASK_DEPLOY_VAULT)
  .addOptionalParam(
    'mockAsset',
    'deploy a mock deposit token',
    {
      deploy: true,
      mintAmount: toBig(1000, 18),
    },
    types.json,
  )
  .setAction(async function (taskArgs: VaultTaskArgs, hre) {
    const { treasury } = await hre.getNamedAccounts()
    const { mockAsset } = taskArgs

    const vaultDeployed = await hre.deployments.getOrNull('vONE')
    let Vault = vaultDeployed?.address ? await hre.ethers.getContractAt('Vault', vaultDeployed.address) : undefined
    if (vaultDeployed) {
      console.log(`Vault already exists @ ${vaultDeployed.address}`)
      Vault = await hre.ethers.getContractAt('Vault', vaultDeployed.address)
    }

    const MockTokenSymbol = 'DAI'

    const seqFeedDeployed = await hre.deployments.getOrNull('MockSequencerUptimeFeed')
    const mockDeployed = await hre.deployments.getOrNull(MockTokenSymbol)
    const mockTokenFeedDeployed = mockDeployed ? await hre.deployments.getOrNull(`${MockTokenSymbol}/USD`) : undefined

    let MockToken = mockDeployed?.address
      ? await hre.ethers.getContractAt('ERC20Mock', mockDeployed.address)
      : undefined
    let MockTokenFeed = mockTokenFeedDeployed?.address
      ? await hre.ethers.getContractAt('MockOracle', mockTokenFeedDeployed.address)
      : undefined
    let SequencerFeed = seqFeedDeployed?.address
      ? await hre.ethers.getContractAt('MockSequencerUptimeFeed', seqFeedDeployed.address)
      : undefined

    if (!MockToken && mockAsset.deploy) {
      console.log(`No mock token exists, deploying ${MockTokenSymbol}`)
      ;[MockToken] = await hre.deploy('ERC20Mock', {
        deploymentName: MockTokenSymbol,
        args: [MockTokenSymbol, MockTokenSymbol, 18, mockAsset?.mintAmount ?? 0],
      })
    }

    if (!MockTokenFeed) {
      console.log(`No feed exists, deploying ${MockTokenSymbol}/USD feed`)
      ;[MockTokenFeed] = await hre.deploy('MockOracle', {
        deploymentName: `MockOracle_${MockTokenSymbol}`,
        args: [`${MockTokenSymbol}/USD`, toBig(1, 8), 8],
      })
    }

    if (!SequencerFeed) {
      console.log('No mock sequencer exists, deploying..')
      ;[SequencerFeed] = await hre.deploy('MockSequencerUptimeFeed')
    }

    const proxies = await hre.ethers.getContractFactory(
      'lib/kopio-lib/src/vendor/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy',
    )

    Vault = await hre.deployProxy('Vault', {
      initializer: 'initialize',
      initializerArgs: ['vONE', 'vONE', 8, hre.users.deployer.address, treasury, SequencerFeed.address],
      type: 'create3',
      salt: 'vault',
      deploymentName: 'vONE',
    })

    if (MockToken) {
      console.log("Adding DAI to Vault's asset list")

      const config: VaultAssetStruct = {
        decimals: 0,
        feed: MockTokenFeed.address,
        token: MockToken.address,
        depositFee: 0,
        withdrawFee: 0,
        maxDeposits: MaxUint128,
        enabled: true,
        staleTime: 86401,
      }
      await Vault.addAsset(config)

      console.log('Approving Vault to spend DAI')
      await MockToken.approve(Vault.address, MAX_UINT_AMOUNT)
    }

    return { Vault, MockToken, MockTokenFeed, SequencerFeed }
  })
