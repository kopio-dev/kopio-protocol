import { createKopio } from '@scripts/create-kopio'
import { expect } from '@test/chai'
import { defaultMintAmount } from '@utils/test/mocks'
import { Role } from '@utils/test/roles'
import { toBig } from '@utils/values'
import { zeroAddress } from 'viem'

describe('Kopio', () => {
  let Kopio: Kopio

  beforeEach(async function () {
    const result = await hre.deployments.fixture('diamond-init')
    if (result.Diamond) {
      hre.Diamond = await hre.getContractOrFork('KopioCore')
    }
    Kopio = (await createKopio('kSYMBOL', 'Kopio SYMBOL', 18, zeroAddress)).Kopio
    // Grant minting rights for test deployer
    await Kopio.grantRole(Role.OPERATOR, hre.addr.deployer)
  })
  describe('#rebase', () => {
    it('can set a positive rebase', async function () {
      const denominator = toBig('1.525')
      const positive = true
      await expect(Kopio.rebase(denominator, positive, [])).to.not.be.reverted
      expect(await Kopio.isRebased()).eq(true)
      const rebaseInfo = await Kopio.rebaseInfo()
      expect(rebaseInfo.denominator).eq(denominator)
      expect(rebaseInfo.positive).eq(true)
    })

    it('can set a negative rebase', async function () {
      const denominator = toBig('1.525')
      const positive = false
      await expect(Kopio.rebase(denominator, positive, [])).to.not.be.reverted
      expect(await Kopio.isRebased()).eq(true)
      const rebaseInfo = await Kopio.rebaseInfo()
      expect(rebaseInfo.denominator).eq(denominator)
      expect(rebaseInfo.positive).eq(false)
    })

    it('can be disabled by setting the denominator to 1 ether', async function () {
      const denominator = toBig(1)
      const positive = false
      await expect(Kopio.rebase(denominator, positive, [])).to.not.be.reverted
      expect(await Kopio.isRebased()).eq(false)
    })

    describe('#balance + supply', () => {
      it('has no effect when not enabled', async function () {
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        expect(await Kopio.isRebased()).eq(false)
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount)
      })

      it('increases balance and supply with positive rebase @ 2', async function () {
        const denominator = 2
        const positive = true
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.rebase(toBig(denominator), positive, [])

        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount.mul(denominator))
        expect(await Kopio.totalSupply()).eq(defaultMintAmount.mul(denominator))
      })

      it('increases balance and supply with positive rebase @ 3', async function () {
        const denominator = 3
        const positive = true
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.rebase(toBig(denominator), positive, [])

        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount.mul(denominator))
        expect(await Kopio.totalSupply()).eq(defaultMintAmount.mul(denominator))
      })

      it('increases balance and supply with positive rebase  @ 100', async function () {
        const denominator = 100
        const positive = true
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.rebase(toBig(denominator), positive, [])

        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount.mul(denominator))
        expect(await Kopio.totalSupply()).eq(defaultMintAmount.mul(denominator))
      })

      it('reduces balance and supply with negative rebase @ 2', async function () {
        const denominator = 2
        const positive = false
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.rebase(toBig(denominator), positive, [])

        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount.div(denominator))
        expect(await Kopio.totalSupply()).eq(defaultMintAmount.div(denominator))
      })

      it('reduces balance and supply with negative rebase @ 3', async function () {
        const denominator = 3
        const positive = false
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.rebase(toBig(denominator), positive, [])

        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount.div(denominator))
        expect(await Kopio.totalSupply()).eq(defaultMintAmount.div(denominator))
      })

      it('reduces balance and supply with negative rebase @ 100', async function () {
        const denominator = 100
        const positive = false
        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.rebase(toBig(denominator), positive, [])

        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(defaultMintAmount.div(denominator))
        expect(await Kopio.totalSupply()).eq(defaultMintAmount.div(denominator))
      })
    })

    describe('#transfer', () => {
      it('has default transfer behaviour after positive rebase', async function () {
        const transferAmount = toBig(1)

        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.mint(hre.addr.userOne, defaultMintAmount)

        const denominator = 2
        const positive = true
        await Kopio.rebase(toBig(denominator), positive, [])

        const rebaseInfodDefaultMintAMount = defaultMintAmount.mul(denominator)

        await Kopio.transfer(hre.addr.userOne, transferAmount)

        expect(await Kopio.balanceOf(hre.addr.userOne)).eq(rebaseInfodDefaultMintAMount.add(transferAmount))
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebaseInfodDefaultMintAMount.sub(transferAmount))
      })

      it('has default transfer behaviour after negative rebase', async function () {
        const transferAmount = toBig(1)

        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.mint(hre.addr.userOne, defaultMintAmount)

        const denominator = 2
        const positive = false
        await Kopio.rebase(toBig(denominator), positive, [])

        const rebaseInfodDefaultMintAMount = defaultMintAmount.div(denominator)

        await Kopio.transfer(hre.addr.userOne, transferAmount)

        expect(await Kopio.balanceOf(hre.addr.userOne)).eq(rebaseInfodDefaultMintAMount.add(transferAmount))
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebaseInfodDefaultMintAMount.sub(transferAmount))
      })

      it('has default transferFrom behaviour after positive rebase', async function () {
        const transferAmount = toBig(1)

        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.mint(hre.addr.userOne, defaultMintAmount)

        const denominator = 2
        const positive = true
        await Kopio.rebase(toBig(denominator), positive, [])

        await Kopio.approve(hre.addr.userOne, transferAmount)

        const rebaseInfodDefaultMintAMount = defaultMintAmount.mul(denominator)

        await Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount)

        expect(await Kopio.balanceOf(hre.addr.userOne)).eq(rebaseInfodDefaultMintAMount.add(transferAmount))
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebaseInfodDefaultMintAMount.sub(transferAmount))

        await expect(Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount))
          .to.be.reverted
        expect(await Kopio.allowance(hre.addr.deployer, hre.addr.userOne)).eq(0)
      })

      it('has default transferFrom behaviour after positive rebase @ 100', async function () {
        const transferAmount = toBig(1)

        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.mint(hre.addr.userOne, defaultMintAmount)

        const denominator = 100
        const positive = true
        await Kopio.rebase(toBig(denominator), positive, [])

        await Kopio.approve(hre.addr.userOne, transferAmount)

        const rebaseInfodDefaultMintAMount = defaultMintAmount.mul(denominator)

        await Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount)

        expect(await Kopio.balanceOf(hre.addr.userOne)).eq(rebaseInfodDefaultMintAMount.add(transferAmount))
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebaseInfodDefaultMintAMount.sub(transferAmount))

        await expect(Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount))
          .to.be.reverted

        expect(await Kopio.allowance(hre.addr.deployer, hre.addr.userOne)).eq(0)
      })

      it('has default transferFrom behaviour after negative rebase', async function () {
        const transferAmount = toBig(1)

        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.mint(hre.addr.userOne, defaultMintAmount)

        const denominator = 2
        const positive = false
        await Kopio.rebase(toBig(denominator), positive, [])

        await Kopio.approve(hre.addr.userOne, transferAmount)

        const rebaseInfodDefaultMintAMount = defaultMintAmount.div(denominator)

        await Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount)

        expect(await Kopio.balanceOf(hre.addr.userOne)).eq(rebaseInfodDefaultMintAMount.add(transferAmount))
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebaseInfodDefaultMintAMount.sub(transferAmount))

        await expect(Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount))
          .to.be.reverted

        expect(await Kopio.allowance(hre.addr.deployer, hre.addr.userOne)).eq(0)
      })

      it('has default transferFrom behaviour after negative rebase @ 100', async function () {
        const transferAmount = toBig(1)

        await Kopio.mint(hre.addr.deployer, defaultMintAmount)
        await Kopio.mint(hre.addr.userOne, defaultMintAmount)

        const denominator = 100
        const positive = false
        await Kopio.rebase(toBig(denominator), positive, [])

        await Kopio.approve(hre.addr.userOne, transferAmount)

        const rebaseInfodDefaultMintAMount = defaultMintAmount.div(denominator)

        await Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount)

        expect(await Kopio.balanceOf(hre.addr.userOne)).eq(rebaseInfodDefaultMintAMount.add(transferAmount))
        expect(await Kopio.balanceOf(hre.addr.deployer)).eq(rebaseInfodDefaultMintAMount.sub(transferAmount))

        await expect(Kopio.connect(hre.users.userOne).transferFrom(hre.addr.deployer, hre.addr.userOne, transferAmount))
          .to.be.reverted

        expect(await Kopio.allowance(hre.addr.deployer, hre.addr.userOne)).eq(0)
      })
    })
  })
})
