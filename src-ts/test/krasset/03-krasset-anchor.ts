import type { KopioShare } from '@/types/typechain'
import { createKopio } from '@scripts/create-kopio'
import { expect } from '@test/chai'
import { defaultMintAmount } from '@utils/test/mocks'
import { Role } from '@utils/test/roles'
import { toBig } from '@utils/values'
import { zeroAddress } from 'viem'

describe('KopioShare', () => {
  let Kopio: Kopio
  let KopioShare: KopioShare

  beforeEach(async function () {
    const result = await hre.deployments.fixture('diamond-init')
    if (result.Diamond) {
      hre.Diamond = await hre.getContractOrFork('KopioCore')
    }
    const deployments = await createKopio('kSYMBOL', 'Kopio SYMBOL', 18, zeroAddress)
    Kopio = deployments.Kopio
    KopioShare = deployments.KopioShare

    // Grant minting rights for test deployer
    await Kopio.grantRole(Role.OPERATOR, hre.addr.deployer)
    // Grant minting rights for test deployer
    await Promise.all([
      Kopio.grantRole(Role.OPERATOR, hre.addr.deployer),
      KopioShare.grantRole(Role.OPERATOR, hre.addr.deployer),
      Kopio.approve(KopioShare.address, hre.ethers.constants.MaxUint256),
    ])
  })

  describe('#minting and burning', () => {
    it('tracks the supply of underlying', async function () {
      await Kopio.mint(hre.addr.deployer, defaultMintAmount)
      expect(await KopioShare.totalAssets()).eq(defaultMintAmount)
      expect(await KopioShare.totalSupply()).eq(0)
      await Kopio.mint(hre.addr.deployer, defaultMintAmount)
      expect(await KopioShare.totalAssets()).eq(defaultMintAmount.add(defaultMintAmount))
      expect(await KopioShare.totalSupply()).eq(0)
    })

    it.skip('mints 1:1 with no rebases', async function () {
      await Kopio.mint(hre.addr.deployer, defaultMintAmount)
      await KopioShare.mint(defaultMintAmount, hre.addr.deployer)

      expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
      expect(await Kopio.balanceOf(KopioShare.address)).eq(defaultMintAmount)
      expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
    })

    it.skip('deposits 1:1 with no rebases', async function () {
      await Kopio.mint(hre.addr.deployer, defaultMintAmount)
      await KopioShare.deposit(defaultMintAmount, hre.addr.deployer)

      expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
      expect(await Kopio.balanceOf(KopioShare.address)).eq(defaultMintAmount)
      expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
    })

    it.skip('redeems 1:1 with no rebases', async function () {
      await Kopio.mint(hre.addr.deployer, defaultMintAmount)
      await KopioShare.mint(defaultMintAmount, hre.addr.deployer)
      await KopioShare.redeem(defaultMintAmount, hre.addr.deployer, hre.addr.deployer)
      expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
      expect(await Kopio.balanceOf(KopioShare.address)).eq(0)
      expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
    })

    it.skip('withdraws 1:1 with no rebases', async function () {
      await Kopio.mint(hre.addr.deployer, defaultMintAmount)
      await KopioShare.deposit(defaultMintAmount, hre.addr.deployer)
      await KopioShare.withdraw(defaultMintAmount, hre.addr.deployer, hre.addr.deployer)
      expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
      expect(await Kopio.balanceOf(KopioShare.address)).eq(0)
      expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
    })

    describe.skip('#rebases', () => {
      describe('#conversions', () => {
        it('mints 1:1 and redeems 1:2 after 1:2 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.mint(defaultMintAmount, hre.addr.deployer)

          const denominator = 2
          const positive = true
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.mul(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.redeem(defaultMintAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })

        it('deposits 1:1 and withdraws 1:2 after 1:2 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.deposit(defaultMintAmount, hre.addr.deployer)

          const denominator = 2
          const positive = true
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.mul(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.withdraw(rebasedAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })

        it('mints 1:1 and redeems 1:6 after 1:6 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.mint(defaultMintAmount, hre.addr.deployer)

          const denominator = 6
          const positive = true
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.mul(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.redeem(defaultMintAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })
        it('deposits 1:1 and withdraws 1:6 after 1:6 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.deposit(defaultMintAmount, hre.addr.deployer)

          const denominator = 6
          const positive = true
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.mul(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.withdraw(rebasedAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })

        it('mints 1:1 and redeems 2:1 after 2:1 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.mint(defaultMintAmount, hre.addr.deployer)

          const denominator = 2
          const positive = false
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.div(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.redeem(defaultMintAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })

        it('deposits 1:1 and withdraws 2:1 after 2:1 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.deposit(defaultMintAmount, hre.addr.deployer)

          const denominator = 2
          const positive = false
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.div(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.withdraw(rebasedAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })

        it('mints 1:1 and redeems 6:1 after 6:1 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.mint(defaultMintAmount, hre.addr.deployer)

          const denominator = 6
          const positive = false
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.div(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.redeem(defaultMintAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })

        it('deposits 1:1 and withdraws 6:1 after 6:1 rebase', async function () {
          await Kopio.mint(hre.addr.deployer, defaultMintAmount)
          await KopioShare.deposit(defaultMintAmount, hre.addr.deployer)

          const denominator = 6
          const positive = false
          await Kopio.rebase(toBig(denominator), positive, [])

          const rebasedAmount = defaultMintAmount.div(denominator)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
          expect(await KopioShare.totalAssets()).eq(rebasedAmount)

          await KopioShare.withdraw(rebasedAmount, hre.addr.deployer, hre.addr.deployer)
          expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebasedAmount)
          expect(await KopioShare.balanceOf(hre.addr.deployer)).eq(0)
          expect(await KopioShare.balanceOf(Kopio.address)).eq(0)
        })
      })
    })
  })
})
