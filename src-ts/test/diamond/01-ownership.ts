import { expect } from '@test/chai'
import { diamondFixture } from '@utils/test/fixtures'
import { Role } from '@utils/test/roles'

describe('Diamond', () => {
  beforeEach(async function () {
    await diamondFixture()
  })
  describe('#ownership', () => {
    it('sets correct owner', async function () {
      expect(await hre.Diamond.owner()).eq(hre.addr.deployer)
    })

    it('sets correct default admin role', async function () {
      expect(await hre.Diamond.hasRole(Role.ADMIN, hre.addr.deployer)).eq(true)
    })

    it('sets a new pending owner', async function () {
      const pendingOwner = hre.users.userOne
      await hre.Diamond.transferOwnership(pendingOwner.address)
      expect(await hre.Diamond.pendingOwner()).eq(pendingOwner.address)
    })
    it('sets the pending owner as new owner', async function () {
      const pendingOwner = hre.users.userOne
      await hre.Diamond.transferOwnership(pendingOwner.address)
      await hre.Diamond.connect(pendingOwner).acceptOwnership()
      expect(await hre.Diamond.owner()).eq(pendingOwner.address)
    })
  })
})
