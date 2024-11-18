import { getLogger } from '@utils/logging'
import { fromBig } from '@utils/values'
import { task, types } from 'hardhat/config'
import type { TaskArguments } from 'hardhat/types'
import { TASK_MINT_OPTIMAL } from './names'

const logger = getLogger(TASK_MINT_OPTIMAL)

task(TASK_MINT_OPTIMAL, 'Mint Kopio with optimal ONE collateral')
  .addParam('kopio', 'Deployment name of the kopio')
  .addParam('amount', 'Amount to mint in decimal', 0, types.float)
  .addParam('pythPayload', 'Path to pyth payload', '', types.json)
  .addOptionalParam('account', 'Account to mint assets for', '', types.string)
  .addOptionalParam('wait', 'wait confirmations', 1, types.int)
  .setAction(async function (taskArgs: TaskArguments, hre) {
    if (taskArgs.amount === 0) {
      throw new Error('Amount should be greater than 0')
    }

    const { deployer } = await hre.ethers.getNamedSigners()

    const accountSupplied = taskArgs.account !== ''
    if (accountSupplied && !hre.ethers.utils.isAddress(taskArgs.account)) {
      throw new Error(`Invalid account address: ${taskArgs.account}`)
    }
    const address = accountSupplied ? taskArgs.account : await deployer.getAddress()
    const signer = await hre.ethers.getSigner(address)
    logger.log('Minting Kopio', taskArgs.kopio, 'with amount', taskArgs.amount, 'for account', signer.address)
    const Protocol = await hre.getContractOrFork('KopioCore')

    const Kopio = (await hre.getContractOrFork('Kopio', taskArgs.kopio)).connect(signer)
    const KopioInfo = await Protocol.getAsset(Kopio.address)

    if (!KopioInfo.isKopio) {
      throw new Error(`Protocol Asset with name ${taskArgs.kopio} does not exist`)
    }
    const mintAmount = hre.ethers.utils.parseUnits(String(taskArgs.amount), 18)
    const mintValue = await Protocol.getValue(Kopio.address, mintAmount)
    const parsedValue = fromBig(mintValue, 8) * 2

    const ONE = (await hre.getContractOrFork('ONE')).connect(signer)

    const ONEAmount = hre.ethers.utils.parseUnits(String(parsedValue), await ONE.decimals())

    const allowance = await ONE.allowance(address, Protocol.address)

    if (!allowance.gt(0)) {
      await ONE.approve(Protocol.address, hre.ethers.constants.MaxUint256)
    }
    await Protocol.depositCollateral(address, ONE.address, ONEAmount)

    logger.log(`Deposited ${parsedValue} ONE for minting ${taskArgs.kopio}`)

    try {
      await Protocol.mintKopio(
        { account: address, kopio: Kopio.address, amount: mintAmount, receiver: address },
        taskArgs.pythPayload,
      )
    } catch (e) {
      logger.error(false, 'Minting failed', e)
    }

    logger.success(`Done minting ${taskArgs.amount} of ${taskArgs.kopio}`)
    return
  })
