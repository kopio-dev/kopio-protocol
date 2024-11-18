import type { KopioShare } from '@/types/typechain'
import { type AllTokenSymbols, getDeploymentUsers } from '@config/hardhat/deploy'
import { getShareMeta } from '@utils/strings'

export async function createKopio<T extends AllTokenSymbols>(
  symbol: T,
  name: string,
  decimals: number,
  underlyingToken: string,
  feeRecipient = hre.users.treasury.address,
  openFee = 0,
  closeFee = 0,
): Promise<{ Kopio: Kopio; KopioShare: KopioShare }> {
  const { deployer } = await hre.ethers.getNamedSigners()
  const { admin } = await getDeploymentUsers(hre)

  const Protocol = await hre.getContractOrFork('KopioCore')

  if (symbol === 'ONE') throw new Error('ONE cannot be created through createKopio')

  if (!hre.DeploymentFactory) {
    ;[hre.DeploymentFactory] = await hre.deploy('ProxyFactory', {
      args: [deployer.address],
    })
  }

  const kopioShare = getShareMeta(symbol, name)
  const exists = await hre.getContractOrNull('Kopio', symbol)
  if (exists) {
    const share = await hre.getContractOrNull('KopioShare', kopioShare.symbol)
    if (share == null) new Error(`Share ${kopioShare.symbol} not found`)
    return {
      Kopio: exists,
      KopioShare: share!,
    }
  }
  const preparedKopio = await hre.prepareProxy('Kopio', {
    deploymentName: symbol,
    initializer: 'initialize',
    initializerArgs: [name, symbol, admin, Protocol.address, underlyingToken, feeRecipient, openFee, closeFee],
    type: 'create3',
    salt: symbol + kopioShare.symbol,
    from: deployer.address,
  })
  const preparedShare = await hre.prepareProxy('KopioShare', {
    initializer: 'initialize',
    deploymentName: kopioShare.symbol,
    constructorArgs: [preparedKopio.proxyAddress],
    initializerArgs: [kopioShare.name, kopioShare.symbol, admin],
    type: 'create3',
    salt: kopioShare.symbol + symbol,
    from: deployer.address,
  })

  const [[Kopio], [KopioShare]] = await hre.deployProxyBatch([preparedKopio, preparedShare] as const, {
    log: true,
  })

  return {
    Kopio,
    KopioShare,
  }
}
