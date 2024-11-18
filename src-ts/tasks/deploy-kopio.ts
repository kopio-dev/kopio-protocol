import { createKopio } from '@scripts/create-kopio'
import { getLogger } from '@utils/logging'
import { task } from 'hardhat/config'
import type { TaskArguments } from 'hardhat/types'
import { zeroAddress } from 'viem'
import { TASK_DEPLOY_KOPIO } from './names'

const logger = getLogger(TASK_DEPLOY_KOPIO)

task(TASK_DEPLOY_KOPIO)
  .addParam('name', 'Name of the token')
  .addParam('symbol', 'Symbol for the token')
  .setAction(async function (taskArgs: TaskArguments) {
    const { name, symbol } = taskArgs
    logger.log('Deploying Kopio', name, symbol)
    const asset = await createKopio(name, symbol, 18, zeroAddress, hre.users.treasury.address, 0, 0)
    logger.success('Deployed Kopio', asset.Kopio.address)
  })
