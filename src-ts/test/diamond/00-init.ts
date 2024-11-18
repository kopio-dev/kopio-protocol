import { expect } from '@test/chai'
import { diamondFixture } from '@utils/test/fixtures'
import hre from 'hardhat'
import type { Facet } from 'hardhat-deploy/dist/types'

describe('Diamond', () => {
  let f: { facets: Facet[] }
  beforeEach(async function () {
    f = await diamondFixture()
  })
  describe('#initialization', () => {
    it('sets correct state', async function () {
      expect(await hre.Diamond.owner()).eq(hre.users.deployer.address)
      expect(await hre.Diamond.initialized()).eq(true)
    })

    it('sets standard facet addresses', async function () {
      const facetAddressesOnChain = (await hre.Diamond.facets()).map(f => f.facetAddress)
      const facetAddressesArtifact = f.facets.map(f => f.facetAddress)

      expect(facetAddressesOnChain.length).eq(facetAddressesArtifact.length)
      expect(facetAddressesOnChain).to.have.members(facetAddressesArtifact)
    })

    it('sets selectors of standard facets', async function () {
      const facetsSelectorsOnChain = (await hre.Diamond.facets()).flatMap(f => f.functionSelectors)
      const facetSelectorsOnArtifact = f.facets.flatMap(f => f.functionSelectors)

      expect(facetsSelectorsOnChain.length).eq(facetSelectorsOnArtifact.length)
      expect(facetsSelectorsOnChain).to.have.members(facetSelectorsOnArtifact)
    })
  })
})
