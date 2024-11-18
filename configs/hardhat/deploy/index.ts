import type { CommonInitializer, ICDPInitializer, SCDPInitializer } from '@/types'
import { envCheck } from '@utils/env'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import { zeroAddress } from 'viem'
import { type assets, testnetConfigs } from './arbitrumSepolia'

envCheck()

export type AllTokenSymbols = TestTokenSymbols | 'ETH' | (typeof assets)[keyof typeof assets]['symbol']

// These function namings are ignored when generating ABI for the diamond
export const signatureFilters = ['init', 'initializer']

export const diamondFacets = ['DiamondCutFacet', 'DiamondLoupeFacet', 'DiamondStateFacet', 'ERC165Facet'] as const

export const commonFacets = [
  'CommonConfigFacet',
  'AuthorizationFacet',
  'CommonStateFacet',
  'AssetStateFacet',
  'AssetConfigFacet',
  'SafetyCouncilFacet',
] as const
export const peripheryFacets = ['DataViewFacet'] as const
export const icdpFacets = [
  'ICDPAccountStateFacet',
  'ICDPBurnFacet',
  'ICDPConfigFacet',
  'ICDPCollateralFacet',
  'ICDPLiquidationFacet',
  'ICDPMintFacet',
  'ICDPStateFacet',
] as const

export const scdpFacets = ['SCDPStateFacet', 'SCDPFacet', 'SCDPConfigFacet', 'SwapFacet', 'SDIFacet'] as const

export const getDeploymentUsers = async (hre: HardhatRuntimeEnvironment) => {
  const users = await hre.getNamedAccounts()
  const Safe = await hre.deployments.getOrNull('GnosisSafeL2')

  const multisig = hre.network.live ? users.multisig : !Safe ? zeroAddress : Safe.address
  return { admin: users.admin, multisig, treasury: users.treasury }
}

export const getICDPInitializer = async (hre: HardhatRuntimeEnvironment): Promise<ICDPInitializer> => {
  return {
    name: 'ICDPConfigFacet',
    args: testnetConfigs[hre.network.name].icdpInitializer,
  }
}
export const getCommonInitializer = async (hre: HardhatRuntimeEnvironment): Promise<CommonInitializer> => {
  const { treasury, admin, multisig } = await getDeploymentUsers(hre)

  const config = testnetConfigs[hre.network.name].commonInitializer

  return {
    name: 'CommonConfigFacet',
    args: {
      ...config,
      admin,
      treasury,
      council: multisig,
      pythEp: hre.network.live ? config.pythEp : (await hre.deployments.get('MockPyth')).address,
      sequencerUptimeFeed: hre.network.live
        ? config.sequencerUptimeFeed
        : (await hre.deployments.get('MockSequencerUptimeFeed')).address,
    },
  }
}
export const getSCDPInitializer = async (hre: HardhatRuntimeEnvironment): Promise<SCDPInitializer> => {
  return {
    name: 'SCDPConfigFacet',
    args: testnetConfigs[hre.network.name].scdpInitializer,
  }
}
