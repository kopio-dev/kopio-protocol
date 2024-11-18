import type { DeployFunction } from 'hardhat-deploy/dist/types'

const deploy: DeployFunction = async function (hre) {
  const { deployer } = await hre.getNamedAccounts()

  const [DeploymentFactory] = await hre.deploy('ProxyFactory', {
    args: [deployer],
  })

  hre.DeploymentFactory = DeploymentFactory

  const [MockMarketStatus] = await hre.deploy('MockMarketStatus')

  hre.Diamond.setMarketStatusProvider(MockMarketStatus.address)
}
deploy.tags = ['local', 'all', 'core', 'proxy']
export default deploy
