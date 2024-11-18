import type { WETH } from '@/types/typechain'
import { expect } from '@test/chai'
import { kopioFixture } from '@utils/test/fixtures'
import { Role } from '@utils/test/roles'
import { toBig } from '@utils/values'

describe('Kopio', () => {
  let Kopio: Kopio
  let wNative: WETH
  let operator: SignerWithAddress
  let user: SignerWithAddress
  let treasury: string
  beforeEach(async function () {
    operator = hre.users.deployer
    user = hre.users.userOne
    treasury = hre.addr.treasury
    ;({ Kopio } = await kopioFixture({
      name: 'Ether',
      symbol: 'kETH',
    }))

    // Deploy WETH
    wNative = (await hre.ethers.deployContract('WETH')) as WETH
    // Give WETH to deployer
    await wNative.connect(user).deposit({ value: toBig(100) })

    await Kopio.connect(hre.users.deployer).grantRole(Role.OPERATOR, operator.address)
    await Kopio.connect(hre.users.deployer).setUnderlying(wNative.address)
    // Approve WETH for Kopio
    await wNative.connect(user).approve(Kopio.address, hre.ethers.constants.MaxUint256)
  })

  describe('Deposit / Wrap', () => {
    it('cannot deposit when paused', async function () {
      await Kopio.connect(operator).pause()
      await expect(Kopio.wrap(user.address, toBig(10))).to.be.revertedWithCustomError(Kopio, 'EnforcedPause')
      await Kopio.connect(operator).unpause()
    })
    it('can deposit with token', async function () {
      await Kopio.connect(user).wrap(user.address, toBig(10))
      expect(await Kopio.balanceOf(user.address)).eq(toBig(10))
    })
    it('cannot deposit native token if not enabled', async function () {
      await expect(user.sendTransaction({ to: Kopio.address, value: toBig(10) })).to.be.reverted
    })
    it('can deposit native token if enabled', async function () {
      await Kopio.connect(operator).enableNative(true)
      const prevBalance = await Kopio.balanceOf(user.address)
      await user.sendTransaction({ to: Kopio.address, value: toBig(10) })
      const currentBalance = await Kopio.balanceOf(user.address)
      expect(currentBalance.sub(prevBalance)).eq(toBig(10))
    })
    it('transfers the correct fees to feeRecipient', async function () {
      await Kopio.connect(operator).setOpenFee(0.1e4)
      await Kopio.connect(operator).enableNative(true)

      let prevBalanceDevOne = await Kopio.balanceOf(user.address)
      const treasuryWETHBal = await wNative.balanceOf(treasury)

      await Kopio.connect(user).wrap(user.address, toBig(10))

      let currentBalanceDevOne = await Kopio.balanceOf(user.address)
      const currentWETHBalanceTreasury = await wNative.balanceOf(treasury)
      expect(currentBalanceDevOne.sub(prevBalanceDevOne)).eq(toBig(9))
      expect(currentWETHBalanceTreasury.sub(treasuryWETHBal)).eq(toBig(1))

      prevBalanceDevOne = await Kopio.balanceOf(user.address)
      const prevBalanceTreasury = await hre.ethers.provider.getBalance(treasury)
      await user.sendTransaction({ to: Kopio.address, value: toBig(10) })
      currentBalanceDevOne = await Kopio.balanceOf(user.address)
      const currentBalanceTreasury = await hre.ethers.provider.getBalance(treasury)
      expect(currentBalanceDevOne.sub(prevBalanceDevOne)).eq(toBig(9))
      expect(currentBalanceTreasury.sub(prevBalanceTreasury)).eq(toBig(1))

      // Set openfee to 0
      await Kopio.connect(operator).setOpenFee(0)
    })
  })
  describe('Withdraw / Unwrap', () => {
    beforeEach(async function () {
      // Deposit some tokens here
      await Kopio.connect(user).wrap(user.address, toBig(10))

      await Kopio.connect(operator).enableNative(true)
      await user.sendTransaction({ to: Kopio.address, value: toBig(100) })
    })
    it('cannot withdraw when paused', async function () {
      await Kopio.connect(operator).pause()
      await expect(Kopio.connect(user).unwrap(user.address, toBig(1), false)).to.be.revertedWithCustomError(
        Kopio,
        'EnforcedPause',
      )
      await Kopio.connect(operator).unpause()
    })
    it('can withdraw', async function () {
      const prevBalance = await wNative.balanceOf(user.address)
      await Kopio.connect(user).unwrap(user.address, toBig(1), false)
      const currentBalance = await wNative.balanceOf(user.address)
      expect(currentBalance).eq(toBig(1).add(prevBalance))
    })
    it('can withdraw native token if enabled', async function () {
      await Kopio.connect(operator).enableNative(true)
      const prevBalance = await Kopio.balanceOf(user.address)
      await Kopio.connect(user).unwrap(user.address, toBig(1), true)
      const currentBalance = await Kopio.balanceOf(user.address)
      expect(prevBalance.sub(currentBalance)).eq(toBig(1))
    })
    it('transfers the correct fees to feeRecipient', async function () {
      // set close fee to 10%
      await Kopio.connect(operator).setCloseFee(0.1e4)

      const prevBalanceDevOne = await wNative.balanceOf(user.address)
      let prevBalanceTreasury = await wNative.balanceOf(treasury)
      await Kopio.connect(user).unwrap(user.address, toBig(9), false)
      const currentBalanceDevOne = await wNative.balanceOf(user.address)
      let currentBalanceTreasury = await wNative.balanceOf(treasury)
      expect(currentBalanceDevOne.sub(prevBalanceDevOne)).eq(toBig(8.1))
      expect(currentBalanceTreasury.sub(prevBalanceTreasury)).eq(toBig(0.9))

      // Withdraw native token and check if fee is transferred
      await user.sendTransaction({ to: Kopio.address, value: toBig(10) })
      prevBalanceTreasury = await hre.ethers.provider.getBalance(treasury)
      await Kopio.connect(user).unwrap(user.address, toBig(9), true)
      currentBalanceTreasury = await hre.ethers.provider.getBalance(treasury)
      expect(currentBalanceTreasury.sub(prevBalanceTreasury)).eq(toBig(0.9))
    })
  })
})
