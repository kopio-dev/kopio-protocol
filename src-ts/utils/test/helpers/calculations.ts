export const ONE_YEAR = 60 * 60 * 24 * 365

export const getBlockTimestamp = async () => {
  const block = await hre.ethers.provider.getBlockNumber()
  const data = await hre.ethers.provider.getBlock(block)
  return data.timestamp
}

export const fromScaledAmount = async (amount: BigNumber, asset: any) => {
  return amount
}

export const toScaledAmount = async (amount: BigNumber, asset: TestKopioAsset, prevDebtIndex?: BigNumber) => {
  return amount
}
