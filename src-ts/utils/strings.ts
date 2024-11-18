import type { AllTokenSymbols } from '@config/hardhat/deploy'

export const getShareMeta = (symbol: AllTokenSymbols, name?: string) => {
  return {
    name: `Kopio Share: ${name || symbol}`,
    symbol: `ks${symbol}`,
  } as const
}
