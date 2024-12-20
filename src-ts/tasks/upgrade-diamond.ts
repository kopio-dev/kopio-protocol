import { icdpFacets } from '@config/hardhat/deploy'
import { updateFacets } from '@scripts/update-facets'
import { getLogger } from '@utils/logging'
import { task } from 'hardhat/config'
import { TASK_UPGRADE_DIAMOND } from './names'

const logger = getLogger(TASK_UPGRADE_DIAMOND)

task(TASK_UPGRADE_DIAMOND, 'Upgrade diamond').setAction(async function (args, hre) {
  logger.log('Upgrading diamond..')
  const [initializer] = await hre.deploy('CommonConfigFacet')

  await updateFacets({
    multisig: true,
    facetNames: icdpFacets,
    initializer: {
      contract: initializer,
      func: 'initializeCommon',
      args: [],
    },
  })
})
