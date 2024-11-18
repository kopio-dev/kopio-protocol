import type { MockContract } from '@defi-wonderland/smock'
import { toBig } from '@utils/values'
import hre from 'hardhat'
import { type Hex, checksumAddress, sliceHex } from 'viem'

const keccak256 = hre.ethers.utils.keccak256
const hexZeroPad = hre.ethers.utils.hexZeroPad
const hexStripZeros = hre.ethers.utils.hexStripZeros
const getStorageAt = hre.ethers.provider.getStorageAt

function hexAdd(hex: string, index: number) {
  return `0x${(BigInt(hex) + BigInt(index)).toString(16)}`
}

async function getMappingArray(slot: string, key: string) {
  const paddedSlot = hexZeroPad(slot, 32)
  const paddedKey = hexZeroPad(key, 32)
  const indexKey = paddedKey + paddedSlot.slice(2)
  const itemSlot = keccak256(indexKey)
  return [keccak256(itemSlot), Number(await getStorageAt(hre.Diamond.address, itemSlot))] as const
}

async function getNestedMappingItem(slot: string, key: string, innerKey: string) {
  const paddedSlot = hexZeroPad(slot, 32)
  const paddedKey = hexZeroPad(key, 32)
  const paddedInnerKey = hexZeroPad(innerKey, 32)
  const indexKey = keccak256(paddedInnerKey + keccak256(paddedKey + paddedSlot.slice(2)).slice(2))
  return await getStorageAt(hre.Diamond.address, indexKey)
}

function toAddr(hex: string) {
  if (hex.length < 64) throw new Error('Invalid value')
  if (hex.length === 64) hex = `0x${hex}`
  return checksumAddress(sliceHex(hex as Hex, 12))
}

export const slots = {
  icdp: '0xa8f8248bd2623d2ac4f9086213698319675a053d994914e3b428d54e1b894d00',
  collateralsOf: 0,
  deposits: 1,
  debt: 2,
  mints: 3,
  feeRecipient: 4,
  maxLiquidationRatio: 5,
  minCollateralRatio: 5,
  liquidationThreshold: 15,
  kopioStorageStart: 208,
  kopioIsRebased: 208,
}
async function loopdy<T>(slot: string, key: string, fn: (slot: string) => Promise<T>) {
  try {
    const [array, length] = await getMappingArray(slot, key)
    return Promise.all(Array.from({ length }).map((_, idx) => fn(hexAdd(array, idx))))
  } catch {
    return []
  }
}

export async function getAccountCollateralAssets(address: string) {
  return await loopdy(hexAdd(slots.icdp, slots.collateralsOf), address, async slot =>
    toAddr(await getStorageAt(hre.Diamond.address, slot)),
  )
}
export async function getAccountMintedAssets(address: string) {
  return loopdy(hexAdd(slots.icdp, slots.mints), address, async slot =>
    toAddr(await getStorageAt(hre.Diamond.address, slot)),
  )
}
export async function getAccountCollateralAmount<T extends Omit<TestKopioAsset, 'deployed'>>(
  address: string,
  asset: string | any,
) {
  return hre.Diamond.getAccountCollateralAmount(address, typeof asset === 'string' ? asset : asset.address)
  // try {
  //   let assetAddress: string = '';
  //   if (typeof asset === 'string') {
  //     assetAddress = asset;
  //   } else {
  //     assetAddress = asset.address;
  //     if ((await getIsRebased(asset.contract))[0]) {
  //       return await hre.Diamond.getAccountCollateralAmount(address, assetAddress);
  //     }
  //   }
  //   const data = await getNestedMappingItem(
  //     hexAdd(slots.icdp, slots.deposits),
  //     address,
  //     assetAddress,
  //   );
  //   return toBig(hexStripZeros(data), 0);
  // } catch {
  //   return toBig(0);
  // }
}
export async function getAccountDebtAmount(address: string, kopio: TestKopioAsset) {
  return hre.Diamond.getAccountDebtAmount(address, kopio.address)
  // try {
  //   if ((await getIsRebased(kopio.contract))[0]) {
  //     return await hre.Diamond.getAccountDebtAmount(address, kopio.address);
  //   }
  //   const data = await getNestedMappingItem(
  //     hexAdd(slots.icdp, slots.debt),
  //     address,
  //     kopio.address,
  //   );
  //   return toBig(hexStripZeros(data), 0);
  // } catch {
  //   return toBig(0);
  // }
}

export async function getMCR() {
  return hre.Diamond.getMCR()
  // try {
  //     const data = await getStorageAt(hre.Diamond.address, hexAdd(slots.icdp, slots.minCollateralRatio));
  //     return BigNumber.from(hexStripZeros(data));
  // } catch {
  //     return BigNumber.from(0);
  // }
}
export async function getMinDebtValue() {
  return hre.Diamond.getMinDebtValue()
  // try {
  //     const data = await getStorageAt(hre.Diamond.address, hexAdd(slots.icdp, slots.minDebtValue));
  //     return BigNumber.from(hexStripZeros(data));
  // } catch {
  //     return BigNumber.from(0);
  // }
}
export async function getLT() {
  return hre.Diamond.getLT()
  // try {
  //     const data = await getStorageAt(hre.Diamond.address, hexAdd(slots.icdp, slots.liquidationThreshold));
  //     return BigNumber.from(hexStripZeros(data));
  // } catch {
  //     return BigNumber.from(0);
  // }
}
export async function getMLR() {
  return hre.Diamond.getMLR()
  // try {
  //     const data = await getStorageAt(hre.Diamond.address, hexAdd(slots.icdp, slots.maxLiquidationRatio));
  //     return BigNumber.from(hexStripZeros(data));
  // } catch {
  //     return BigNumber.from(0);
  // }
}
export async function getIsRebased<T extends Kopio | ERC20Upgradeable>(asset: MockContract<T>) {
  let denominator = toBig(0)
  let isRebased = false
  let isPositive = false

  // @ts-expect-error
  if (typeof asset.isRebased !== 'function') return [Boolean(false), isPositive, denominator] as const

  try {
    isPositive = Boolean(Number(await getStorageAt(asset.address, slots.kopioIsRebased)))
    try {
      denominator = toBig(hexStripZeros(await getStorageAt(asset.address, slots.kopioIsRebased + 1)), 0)
    } catch {}
    isRebased = denominator.gt(toBig(1))
  } catch {
    // @ts-expect-error
    isRebased = await asset.isRebased()
  }
  return [isRebased, isPositive, denominator] as const
}

export async function getAccountDepositIndex(address: string, asset: string) {
  try {
    const assets = await getAccountCollateralAssets(address)
    return assets.indexOf(asset as Hex)
  } catch {
    return hre.Diamond.getAccountDepositIndex(address, asset)
  }
}
export async function getAccountMintIndex(address: string, asset: string) {
  try {
    const assets = await getAccountMintedAssets(address)
    return assets.indexOf(asset as Hex)
  } catch {
    return hre.Diamond.getAccountMintIndex(address, asset)
  }
}

export default {
  getIsRebased,
  getAccountMintedAssets,
  getAccountCollateralAssets,
  getAccountDebtAmount,
  getAccountCollateralAmount,
  getMLR,
  getMCR,
  getMinDebtValue,
  getLT,
  getAccountDepositIndex,
  getAccountMintIndex,
}
