import { getLogger } from '@utils/logging'
import { addMockKopio } from '@utils/test/helpers/assets'
import { addMockExtAsset } from '@utils/test/helpers/collaterals'
import { testCollateralConfig, testKopioConfig } from '@utils/test/mocks'
import type { DeployFunction } from 'hardhat-deploy/dist/types'

const func: DeployFunction = async function (hre) {
  const logger = getLogger('mock-assets')
  if (!hre.Diamond) {
    throw new Error('No diamond deployed')
  }

  await addMockExtAsset()
  await addMockExtAsset({
    ...testCollateralConfig,
    ticker: 'Collateral2',
    symbol: 'Collateral2',
    pyth: {
      id: 'Collateral2',
      invert: false,
    },
    decimals: 18,
  })
  await addMockExtAsset({
    ...testCollateralConfig,
    ticker: 'Coll8Dec',
    symbol: 'Coll8Dec',
    pyth: {
      id: 'Coll8Dec',
      invert: false,
    },
    decimals: 8,
  })
  await addMockKopio()
  await addMockKopio({
    ...testKopioConfig,
    ticker: 'Kopio2',
    symbol: 'Kopio2',
    pyth: {
      id: 'Kopio2',
      invert: false,
    },
  })
  await addMockKopio({
    ...testKopioConfig,
    ticker: 'Kopio3',
    symbol: 'Kopio3',
    pyth: {
      id: 'Kopio3',
      invert: false,
    },
    collateralConfig: testCollateralConfig.collateralConfig,
  })

  logger.log('Added mock assets')
}

func.tags = ['local', 'icdp-test', 'mock-assets']
func.dependencies = ['icdp-init']

func.skip = async hre => hre.network.name !== 'hardhat'
export default func
