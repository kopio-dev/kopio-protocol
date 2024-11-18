import { expect } from '@test/chai'
import { kopioFixture } from '@utils/test/fixtures'
import { Role } from '@utils/test/roles'
import { zeroAddress } from 'viem'

describe('Kopio', () => {
  let Kopio: Kopio

  beforeEach(async function () {
    ;({ Kopio } = await kopioFixture({ name: 'Ether', symbol: 'kETH', underlyingToken: zeroAddress }))
    this.mintAmount = 125
    this.owner = hre.users.deployer
    await Kopio.grantRole(Role.OPERATOR, this.owner.address)
  })

  describe('#mint', () => {
    it('should allow the owner to mint to their own address', async function () {
      expect(await Kopio.totalSupply()).eq(0)
      expect(await Kopio.balanceOf(this.owner.address)).eq(0)

      await Kopio.connect(this.owner).mint(this.owner.address, this.mintAmount)

      // Check total supply and owner's balances increased
      expect(await Kopio.totalSupply()).eq(this.mintAmount)
      expect(await Kopio.balanceOf(this.owner.address)).eq(this.mintAmount)
    })

    it('should allow the asset owner to mint to another address', async function () {
      expect(await Kopio.totalSupply()).eq(0)
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(0)

      await Kopio.connect(this.owner).mint(hre.users.userOne.address, this.mintAmount)

      // Check total supply and user's balances increased
      expect(await Kopio.totalSupply()).eq(this.mintAmount)
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(this.mintAmount)
    })

    it('should not allow non-owner addresses to mint tokens', async function () {
      expect(await Kopio.totalSupply()).eq(0)
      expect(await Kopio.balanceOf(this.owner.address)).eq(0)

      await expect(Kopio.connect(hre.users.userOne).mint(this.owner.address, this.mintAmount)).to.be.reverted

      // Check total supply and all account balances unchanged
      expect(await Kopio.totalSupply()).eq(0)
      expect(await Kopio.balanceOf(this.owner.address)).eq(0)
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(0)
    })

    it('should not allow admin to mint tokens', async function () {
      await Kopio.renounceRole(Role.OPERATOR, this.owner.address)
      await expect(Kopio.connect(this.owner).mint(this.owner.address, this.mintAmount)).to.be.reverted
    })
  })

  describe('#burn', () => {
    beforeEach(async function () {
      await Kopio.connect(this.owner).mint(hre.users.userOne.address, this.mintAmount)
      this.owner = hre.users.deployer
      this.mintAmount = 125
      await Kopio.grantRole(Role.OPERATOR, this.owner.address)
    })

    it("should allow the owner to burn tokens from user's address (without token allowance)", async function () {
      expect(await Kopio.totalSupply()).eq(this.mintAmount)

      await Kopio.connect(this.owner).burn(hre.users.userOne.address, this.mintAmount)

      // Check total supply and user's balances decreased
      expect(await Kopio.totalSupply()).eq(0)
      expect(await Kopio.balanceOf(this.owner.address)).eq(0)
      // Confirm that owner doesn't hold any tokens
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(0)
    })

    it("should allow the operator to burn tokens from user's address without changing existing allowances", async function () {
      await Kopio.connect(this.owner).approve(hre.users.userOne.address, this.mintAmount)

      expect(await Kopio.totalSupply()).eq(this.mintAmount)
      expect(await Kopio.allowance(this.owner.address, hre.users.userOne.address)).eq(this.mintAmount)

      await Kopio.connect(this.owner).burn(hre.users.userOne.address, this.mintAmount)

      // Check total supply and user's balances decreased
      expect(await Kopio.totalSupply()).eq(0)
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(0)
      // Confirm that owner doesn't hold any tokens
      expect(await Kopio.balanceOf(this.owner.address)).eq(0)
      // Confirm that token allowances are unchanged
      expect(await Kopio.allowance(this.owner.address, hre.users.userOne.address)).eq(this.mintAmount)
    })

    it('should not allow the operator to burn more tokens than user holds', async function () {
      const userBalance = await Kopio.balanceOf(hre.users.userOne.address)
      const overUserBalance = Number(userBalance) + 1

      await expect(Kopio.connect(this.owner).burn(hre.users.userOne.address, overUserBalance)).to.be.reverted

      // Check total supply and user's balances are unchanged
      expect(await Kopio.totalSupply()).eq(this.mintAmount)
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(this.mintAmount)
    })

    it('should not allow non-operator addresses to burn tokens', async function () {
      await expect(Kopio.connect(hre.users.userTwo).burn(hre.users.userOne.address, this.mintAmount))
        .to.be.revertedWithCustomError(Kopio, 'AccessControlUnauthorizedAccount')
        .withArgs(hre.users.userTwo.address, Role.OPERATOR)

      // Check total supply and user's balances unchanged
      expect(await Kopio.totalSupply()).eq(this.mintAmount)
      expect(await Kopio.balanceOf(hre.users.userOne.address)).eq(this.mintAmount)
    })
  })
})
