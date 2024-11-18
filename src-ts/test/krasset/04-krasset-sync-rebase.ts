import { addLiquidity } from '@utils/test/helpers/amm'
import { mintKopio } from '@utils/test/helpers/assets'
import { depositMockCollateral } from '@utils/test/helpers/collaterals'
import { defaultMintAmount, testCollateralConfig } from '@utils/test/mocks'
import { Role } from '@utils/test/roles'
import { toBig } from '@utils/values'
import { expect } from 'chai'

describe.skip('Test Kopio with Rebase and sync', () => {
  let Kopio: TestKopioAsset

  beforeEach(async function () {
    Kopio = this.kopios.find(asset => asset.config.args.symbol === 'Kopio')!

    const ONE = await hre.getContractOrFork('ONE')
    // [hre.UniV2Factory] = await hre.deploy("UniswapV2Factory", {
    //     args: [hre.users.deployer.address],
    // });
    // [hre.UniV2Router] = await hre.deploy("UniswapV2Router02", {
    //     args: [hre.UniV2Factory.address, (await hre.deploy("WETH"))[0].address],
    // });

    await depositMockCollateral({
      user: hre.users.userNine,
      asset: this.collaterals.find(c => c.config.args.ticker === testCollateralConfig.ticker)!,
      amount: toBig(100000),
    })
    await mintKopio({
      user: hre.users.userNine,
      asset: Kopio,
      amount: toBig(64),
    })
    await mintKopio({
      user: hre.users.userNine,
      asset: ONE,
      amount: toBig(1000),
    })
    this.pool = await addLiquidity({
      user: hre.users.userNine,
      router: hre.UniV2Router,
      token0: Kopio,
      token1: {
        address: ONE.address,
        contract: ONE,
      } as any,
      amount0: toBig(64),
      amount1: toBig(1000),
    })

    await Kopio.contract.grantRole(Role.OPERATOR, hre.addr.deployer)
  })

  it('Rebases the asset with no sync of uniswap pools - Reserves not updated', async function () {
    const denominator = 2
    const positive = true
    const beforeTotalSupply = await Kopio.contract.totalSupply()

    const [beforeReserve0, beforeReserve1, beforeTimestamp] = await this.pool.getReserves()

    await Kopio.contract.mint(hre.addr.deployer, defaultMintAmount)
    const deployerBalanceBefore = await Kopio.contract.balanceOf(hre.addr.deployer)
    await Kopio.contract.rebase(toBig(denominator), positive, [])

    const [afterReserve0, afterReserve1, afterTimestamp] = await this.pool.getReserves()

    expect(await Kopio.contract.balanceOf(hre.addr.deployer)).eq(deployerBalanceBefore.mul(denominator))
    expect(await Kopio.contract.totalSupply()).eq(beforeTotalSupply.add(defaultMintAmount).mul(denominator))

    expect(afterReserve0).eq(beforeReserve0)
    expect(afterReserve1).eq(beforeReserve1)
    expect(beforeTimestamp).eq(afterTimestamp)
  })

  it('Rebases the asset with sync of uniswap pools - Reserve should be updated', async function () {
    const denominator = 2
    const positive = true

    const [beforeReserve0, beforeReserve1, beforeTimestamp] = await this.pool.getReserves()

    await Kopio.contract.rebase(toBig(denominator), positive, [this.pool.address])

    const [afterReserve0, afterReserve1, afterTimestamp] = await this.pool.getReserves()

    if (beforeReserve0.eq(afterReserve0)) {
      expect(afterReserve1).eq(beforeReserve1.mul(denominator))
    } else {
      expect(afterReserve0).eq(beforeReserve0.mul(denominator))
    }
    expect(afterTimestamp).to.gt(beforeTimestamp)
  })
})
