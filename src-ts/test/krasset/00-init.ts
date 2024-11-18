import { expect } from '@test/chai'
import { getShareMeta } from '@utils/strings'
import { kopioFixture } from '@utils/test/fixtures'
import { Role } from '@utils/test/roles'
import { zeroAddress } from 'viem'

const name = 'Ether'
const symbol = 'kETH'
const share = getShareMeta(symbol, name)
describe('Kopio', function () {
  let f: Awaited<ReturnType<typeof kopioFixture>>

  beforeEach(async function () {
    f = await kopioFixture({ name, symbol, underlyingToken: zeroAddress })
  })

  describe('Kopio', function () {
    describe('#initialization', () => {
      it('cant initialize twice', async function () {
        await expect(
          f.Kopio.initialize(
            name,
            symbol,
            hre.addr.deployer,
            hre.Diamond.address,
            hre.ethers.constants.AddressZero,
            hre.addr.deployer,
            0,
            0,
          ),
        ).to.be.reverted
      })

      it.skip('cant initialize implementation', async function () {
        const deployment = await hre.deployments.get(symbol)
        const implementationAddress = deployment!.implementation
        expect(implementationAddress).not.eq(hre.ethers.constants.AddressZero)
        const KopioImpl = await hre.ethers.getContractAt('Kopio', implementationAddress!)

        await expect(
          KopioImpl.initialize(
            name,
            symbol,
            hre.addr.deployer,
            hre.Diamond.address,
            hre.ethers.constants.AddressZero,
            hre.addr.deployer,
            0,
            0,
          ),
        ).to.be.reverted
      })

      it('sets correct state', async function () {
        expect(await f.Kopio.name()).eq(name)
        expect(await f.Kopio.symbol()).eq(symbol)
        expect(await f.Kopio.protocol()).eq(hre.Diamond.address)
        expect(await f.Kopio.hasRole(Role.DEFAULT_ADMIN, hre.addr.deployer)).eq(true)
        expect(await f.Kopio.hasRole(Role.ADMIN, hre.addr.deployer)).eq(true)
        expect(await f.Kopio.hasRole(Role.OPERATOR, hre.Diamond.address)).eq(true)

        expect(await f.Kopio.totalSupply()).eq(0)
        expect(await f.Kopio.isRebased()).eq(false)

        const rebaseInfo = await f.Kopio.rebaseInfo()
        expect(rebaseInfo.denominator).eq(0)
        expect(rebaseInfo.positive).eq(false)
      })

      it('can reinitialize metadata', async function () {
        const newName = 'foo'
        const newSymbol = 'bar'
        await expect(f.Kopio.reinitializeERC20(newName, newSymbol, 2)).to.not.be.reverted
        expect(await f.Kopio.name()).eq(newName)
        expect(await f.Kopio.symbol()).eq(newSymbol)
      })
    })

    it('sets correct state', async function () {
      expect(await f.Kopio.name()).eq(name)
      expect(await f.Kopio.symbol()).eq(symbol)
      expect(await f.Kopio.protocol()).eq(hre.Diamond.address)
      expect(await f.Kopio.hasRole(Role.ADMIN, hre.addr.deployer)).eq(true)
      expect(await f.Kopio.hasRole(Role.OPERATOR, hre.Diamond.address)).eq(true)

      expect(await f.Kopio.totalSupply()).eq(0)
      expect(await f.Kopio.isRebased()).eq(false)

      const rebaseInfo = await f.Kopio.rebaseInfo()
      expect(rebaseInfo.denominator).eq(0)
      expect(rebaseInfo.positive).eq(false)
    })

    it('can reinitialize metadata', async function () {
      const newName = 'foo'
      const newSymbol = 'bar'
      await expect(f.Kopio.reinitializeERC20(newName, newSymbol, 2)).to.not.be.reverted
      expect(await f.Kopio.name()).eq(newName)
      expect(await f.Kopio.symbol()).eq(newSymbol)
    })
  })

  describe('#initialization - share', () => {
    it('cant initialize twice', async function () {
      await expect(f.KopioShare.initialize(name!, symbol, hre.addr.deployer)).to.be.reverted
    })
    it('sets correct state', async function () {
      expect(await f.KopioShare.name()).eq(share.name)
      expect(await f.KopioShare.symbol()).eq(share.symbol)
      expect(await f.KopioShare.asset()).eq(f.Kopio.address)
      expect(await f.KopioShare.hasRole(Role.ADMIN, hre.addr.deployer)).eq(true)
      expect(await f.KopioShare.hasRole(Role.OPERATOR, hre.Diamond.address)).eq(true)

      expect(await f.KopioShare.totalSupply()).eq(0)
      expect(await f.KopioShare.totalAssets()).eq(await f.Kopio.totalSupply())

      const rebaseInfo = await f.Kopio.rebaseInfo()
      expect(rebaseInfo.denominator).eq(0)
      expect(rebaseInfo.positive).eq(false)
    })

    it('cant initialize implementation', async function () {
      const deployment = await hre.deployments.get(share.symbol)
      const implementationAddress = deployment!.implementation

      expect(implementationAddress).not.eq(hre.ethers.constants.AddressZero)
      const KopioShareImpl = await hre.ethers.getContractAt('KopioShare', implementationAddress!)

      await expect(KopioShareImpl.initialize(name!, symbol, hre.addr.deployer)).to.be.reverted
    })

    it('can reinitialize metadata', async function () {
      const newName = 'foo'
      const newSymbol = 'bar'
      await expect(f.KopioShare.reinitializeERC20(newName, newSymbol, 2)).to.not.be.reverted
      expect(await f.KopioShare.name()).eq(newName)
      expect(await f.KopioShare.symbol()).eq(newSymbol)
      await f.KopioShare.reinitializeERC20(name!, symbol, 3)
    })
  })
})
