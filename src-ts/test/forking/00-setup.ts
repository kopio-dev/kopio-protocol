import { icdpFacets } from '@config/hardhat/deploy'
import { updateFacets } from '@scripts/update-facets'
import { expect } from '@test/chai'
import { toBig } from '@utils/values'
;(process.env.FORKING ? describe : describe.skip)('Forking', () => {
  describe('#setup', () => {
    it('should get Protocol from the companion network locally', async function () {
      expect(hre.companionNetworks).to.have.property('live')

      const Protocol = await hre.getContractOrFork('KopioCore')
      expect(await Protocol.initialized()).eq(true)

      // const Safe = await hre.getContractOrFork("GnosisSafeL2", "Multisig");
      // expect(await Protocol.hasRole(Role.DEFAULT_ADMIN, Safe.address)).to.be.true;
    })
  })
  describe('#rate-upgrade-11-04-2023', () => {
    it.skip('should be able to deploy facets', async function () {
      expect(hre.companionNetworks).to.have.property('live')
      const { deployer } = await hre.getNamedAccounts()
      const Protocol = await hre.getContractOrFork('KopioCore')
      const kETH = await hre.getContractOrFork('Kopio', 'kETH')

      const facetsBefore = await Protocol.facets()
      const { facetsAfter } = await updateFacets({ facetNames: icdpFacets })
      expect(facetsAfter).to.not.deep.eq(facetsBefore)

      await expect(
        Protocol.mintKopio({ account: deployer, kopio: kETH.address, amount: toBig(0.1), receiver: deployer }, []),
      ).to.not.be.reverted
    })
  })
})
