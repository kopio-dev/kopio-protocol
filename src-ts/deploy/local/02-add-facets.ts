import {
  commonFacets,
  getCommonInitializer,
  getICDPInitializer,
  getSCDPInitializer,
  icdpFacets,
  peripheryFacets,
  scdpFacets,
} from '@config/hardhat/deploy'
import { addFacets } from '@scripts/add-facets'
import { getLogger } from '@utils/logging'
import type { DeployFunction } from 'hardhat-deploy/dist/types'
import { encodeAbiParameters, encodeFunctionData, parseAbiParameters, zeroAddress } from 'viem'

const logger = getLogger('common-facets')

const deploy: DeployFunction = async function (hre) {
  if (!hre.Diamond.address) {
    throw new Error('Diamond not deployed')
  }

  await hre.deploy('MockPyth', {
    args: [[]],
  })
  await hre.deploy('MockSequencerUptimeFeed')

  const commonInit = (await getCommonInitializer(hre)).args
  if (commonInit.council === zeroAddress) throw new Error('Council address not set')
  await addFacets({
    names: commonFacets,
    initializerName: 'CommonConfigFacet',
    initializerFunction: 'initializeCommon',
    initializerArgs: commonInit,
  })
  logger.success('Added: Common facets')

  await addFacets({
    names: icdpFacets,
    initializerName: 'ICDPConfigFacet',
    initializerFunction: 'initializeICDP',
    initializerArgs: (await getICDPInitializer(hre)).args,
  })
  logger.success('Added: ICDP Facets')

  await addFacets({
    names: scdpFacets,
    initializerName: 'SCDPConfigFacet',
    initializerFunction: 'initializeSCDP',
    initializerArgs: (await getSCDPInitializer(hre)).args,
  })
  logger.success('Added: SCDP facets.')
  await addFacets({
    names: peripheryFacets,
  })

  logger.success('Added: Periphery facets.')
}

deploy.tags = ['all', 'local', 'core', 'facets']
deploy.dependencies = ['diamond', 'safe']
deploy.skip = async hre => hre.network.live

export default deploy
