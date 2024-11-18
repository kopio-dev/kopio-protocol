import { Err__factory } from '@/types/typechain'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

export const Errors = (hre: HardhatRuntimeEnvironment) => {
  return Err__factory.connect(hre.Diamond.address, hre.Diamond.provider)
}
