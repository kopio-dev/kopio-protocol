import { testnetConfigs } from '@config/hardhat/deploy/arbitrumSepolia'
import { TASK_MINT_OPTIMAL } from '@tasks'
import { getLogger } from '@utils/logging'
import { fromBig, toBig } from '@utils/values'
import type { DeployFunction } from 'hardhat-deploy/dist/types'
import { getPayloadHardhat } from 'utils/pyth-hardhat'

const logger = getLogger('mint-kopios')

const deploy: DeployFunction = async function (hre) {
  const kopios = testnetConfigs[hre.network.name].assets.filter(a => !!a.kopioConfig)

  const protocol = await hre.getContractOrFork('KopioCore')
  const { deployer } = await hre.ethers.getNamedSigners()

  const DAI = await hre.getContractOrFork('ERC20Mock', 'DAI')

  await DAI.mint(deployer.address, toBig(2_500_000_000))
  await DAI.approve(protocol.address, hre.ethers.constants.MaxUint256)
  await protocol.connect(deployer).depositCollateral(deployer.address, DAI.address, toBig(2_500_000_000))

  const pythPayload = await getPayloadHardhat(testnetConfigs[hre.network.name].assets)
  const ONE = await hre.getContractOrFork('ONE')
  await protocol.connect(deployer).mintKopio(
    {
      account: deployer.address,
      kopio: ONE.address,
      amount: toBig(1_200_000_000),
      receiver: deployer.address,
    },
    pythPayload,
  )

  for (const kopio of kopios) {
    const asset = await hre.getContractOrFork('Kopio', kopio.symbol)
    const debt = await protocol.getAccountDebtAmount(deployer.address, asset.address)

    if (!kopio.mintAmount || debt.gt(0) || kopio.symbol === 'ONE') {
      logger.log(`Skipping minting ${kopio.symbol}`)
      continue
    }
    logger.log(`minting ${kopio.mintAmount} of ${kopio.name}`)

    await hre.run(TASK_MINT_OPTIMAL, {
      protocolAsset: kopio.symbol,
      amount: kopio.mintAmount,
      pythPayload,
    })
  }
}
deploy.tags = ['all', 'local', 'mint-kopios']
deploy.dependencies = ['configuration']

deploy.skip = async hre => {
  if (hre.network.name === 'hardhat') {
    logger.log('Skip: Mint Kopios, is hardhat network')
    return true
  }
  const kopios = testnetConfigs[hre.network.name].assets.filter(a => !!a.kopioConfig)
  if (!kopios.length) {
    logger.log('Skip: Mint Kopios, no kopios configured')
    return true
  }

  const protocol = await hre.getContractOrFork('KopioCore')
  const lastAsset = await hre.deployments.get(kopios[kopios.length - 1].symbol)

  const { deployer } = await hre.getNamedAccounts()
  if (fromBig(await protocol.getAccountDebtAmount(deployer, lastAsset.address)) > 0) {
    logger.log('Skip: Mint kopios, already minted.')
    return true
  }
  return false
}

export default deploy
