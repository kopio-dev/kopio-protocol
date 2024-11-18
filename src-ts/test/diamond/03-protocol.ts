import {
  commonFacets,
  diamondFacets,
  getCommonInitializer,
  getICDPInitializer,
  getSCDPInitializer,
  icdpFacets,
  peripheryFacets,
  scdpFacets,
} from '@config/hardhat/deploy'
import { expect } from '@test/chai'
import { defaultFixture } from '@utils/test/fixtures'
import { Role } from '@utils/test/roles'

describe('Diamond', () => {
  beforeEach(async function () {
    await defaultFixture()
  })
  describe('#protocol initialization', () => {
    it('initialized all facets', async function () {
      const facetsOnChain = (await hre.Diamond.facets()).map(([facetAddress, functionSelectors]) => ({
        facetAddress,
        functionSelectors,
      }))
      const expectedFacets = await Promise.all(
        [...diamondFacets, ...icdpFacets, ...scdpFacets, ...commonFacets, ...peripheryFacets].map(async name => {
          const deployment = await hre.deployments.get(name)
          return {
            facetAddress: deployment.address,
            functionSelectors: facetsOnChain.find(f => f.facetAddress === deployment.address)!.functionSelectors,
          }
        }),
      )
      expect(facetsOnChain).to.have.deep.members(expectedFacets)
    })
    it('initialized correct state', async function () {
      expect(await hre.Diamond.getStorageVersion()).eq(3)
      const { args } = await getCommonInitializer(hre)
      const icdpInit = (await getICDPInitializer(hre)).args
      const scdpInit = (await getSCDPInitializer(hre)).args

      expect(await hre.Diamond.hasRole(Role.ADMIN, args.admin)).eq(true)
      expect(await hre.Diamond.hasRole(Role.SAFETY_COUNCIL, hre.Multisig.address)).eq(true)

      expect(await hre.Diamond.getFeeRecipient()).eq(args.treasury)
      expect(await hre.Diamond.getPythEndpoint()).eq(args.pythEp)
      expect(await hre.Diamond.getMCR()).eq(icdpInit.minCollateralRatio)
      expect(await hre.Diamond.getLT()).eq(icdpInit.liquidationThreshold)
      expect(await hre.Diamond.getMinDebtValue()).eq(icdpInit.minDebtValue)
      expect(await hre.Diamond.getMLR()).eq(Number(icdpInit.liquidationThreshold) + 0.01e4)

      const scdpParams = await hre.Diamond.getGlobalParameters()
      expect(scdpParams.minCollateralRatio).eq(scdpInit.minCollateralRatio)
      expect(scdpParams.liquidationThreshold).eq(scdpInit.liquidationThreshold)
      expect(await hre.Diamond.getOracleDeviationPct()).eq(args.maxPriceDeviationPct)
    })

    it('can modify configuration parameters', async function () {
      await expect(hre.Diamond.setOracleDeviation(0.05e4)).to.not.be.reverted
      await expect(hre.Diamond.setSequencerGracePeriod(1000)).to.not.be.reverted
      await expect(hre.Diamond.setOracleDecimals(9)).to.not.be.reverted
      await expect(hre.Diamond.setMinDebtValue(20e8)).to.not.be.reverted

      expect(await hre.Diamond.getMinDebtValue()).eq(20e8)
      expect(await hre.Diamond.getOracleDecimals()).eq(9)
      expect(await hre.Diamond.getOracleDeviationPct()).eq(0.05e4)
      expect(await hre.Diamond.getSequencerGracePeriod()).eq(1000)
    })
  })
})
