import type { KopioShare, ERC20Mock } from '@/types/typechain'
import type { MockContract } from '@defi-wonderland/smock'
import { toBig } from '@utils/values'
import { getIsRebased } from './optimizations'

export function setKopioBalanceFunc(kopio: MockContract<Kopio>, share: MockContract<KopioShare>) {
  return async (user: SignerWithAddress, amount: BigNumber, allowanceFor?: string) => {
    let supply = toBig(0)
    let shareSupply = toBig(0)
    let diamondBal = toBig(0)

    // faster than calls if no rebase..
    try {
      const [isRebased] = await getIsRebased(kopio)
      supply = isRebased ? await kopio.totalSupply() : ((await kopio.getVariable('_totalSupply')) as BigNumber)
      shareSupply = isRebased ? ((await share.getVariable('_totalSupply')) as BigNumber) : supply
      diamondBal = isRebased
        ? await kopio.balanceOf(hre.Diamond.address)
        : ((await kopio.getVariable('_balances', [hre.Diamond.address])) as BigNumber)
    } catch {}

    await Promise.all([
      share.setVariables({
        _totalSupply: shareSupply.add(amount),
        _balances: {
          [hre.Diamond.address]: diamondBal.add(amount),
        },
      }),
      kopio.setVariables({
        _totalSupply: supply.add(amount),
        _balances: {
          [user.address]: amount,
        },
        _allowances: allowanceFor && {
          [user.address]: {
            [allowanceFor]: hre.ethers.constants.MaxInt256, // doesnt work with uint
          },
        },
      }),
    ])
  }
}

export function setBalanceCollateralFunc(collateral: MockContract<ERC20Mock>) {
  return async (user: SignerWithAddress, amount: BigNumber, allowanceFor?: string) => {
    let tSupply = toBig(0)
    try {
      tSupply = (await collateral.getVariable('_totalSupply')) as BigNumber
    } catch {}

    return collateral.setVariables({
      _totalSupply: tSupply.add(amount),
      _balances: {
        [user.address]: amount,
      },
      _allowances: allowanceFor && {
        [user.address]: {
          [allowanceFor]: hre.ethers.constants.MaxInt256, // doesnt work with uint
        },
      },
    })
  }
}

export function getBalanceCollateralFunc(collateral: MockContract<ERC20Mock>) {
  // return (acc: any) => collateral.balanceOf(acc)
  return async (account: string | SignerWithAddress) => {
    let balance = toBig(0)
    try {
      balance = (await collateral.getVariable('_balances', [
        typeof account === 'string' ? account : account.address,
      ])) as BigNumber
    } catch {}

    return balance
  }
}

export function getKopioBalanceFunc(kopio: MockContract<Kopio>) {
  return async (account: string | SignerWithAddress) => {
    let balance = toBig(0)
    try {
      const [isRebased] = await getIsRebased(kopio)
      balance = isRebased
        ? await kopio.balanceOf(account)
        : ((await kopio.getVariable('_balances', [
            typeof account === 'string' ? account : account.address,
          ])) as BigNumber)
    } catch {}

    return balance
  }
}
