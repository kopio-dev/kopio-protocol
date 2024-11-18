import { ICDPFee } from '@/types'
import type {
  FeePaidEventObject,
  KopioBurnedEventObject,
  KopioMintedEventObject,
} from '@/types/typechain/src/contracts/interfaces/KopioCore'
import { getStorageAt } from '@nomicfoundation/hardhat-network-helpers'
import { Errors } from '@utils/errors'
import { getInternalEvent } from '@utils/events'
import { type MintRepayFixture, mintRepayFixture } from '@utils/test/fixtures'
import { burnKopio, getDebtIndexAdjustedBalance, mintKopio } from '@utils/test/helpers/assets'
import { fromScaledAmount, toScaledAmount } from '@utils/test/helpers/calculations'
import { withdrawCollateral } from '@utils/test/helpers/collaterals'
import optimized from '@utils/test/helpers/optimizations'
import { TEN_USD } from '@utils/test/mocks'
import { Role } from '@utils/test/roles'
import { MaxUint128, fromBig, toBig } from '@utils/values'
import { expect } from 'chai'

describe('ICDP', function () {
  let f: MintRepayFixture

  beforeEach(async function () {
    f = await mintRepayFixture()
    await f.reset()
  })
  this.slow(200)
  describe('#mint+burn', () => {
    describe('#mint', () => {
      it('should allow users to mint whitelisted assets backed by collateral', async function () {
        const kopioSupplyBefore = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyBefore).eq(f.initialMintAmount)
        // Initially, the array of the user's minted assets should be empty.
        const mintedAssetsBefore = await hre.Diamond.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsBefore).to.deep.eq([])

        // Mint assets
        const mintAmount = toBig(10)
        await f.User1.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
          hre.updateData(),
        )

        // Confirm the array of the user's minted assets has been pushed to.
        const mintedAssetsAfter = await hre.Diamond.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])
        // Confirm the amount minted is recorded for the user.
        const amountMinted = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
        expect(amountMinted).eq(mintAmount)
        // Confirm the user's assets balance has increased
        const userBalance = await f.Kopio.contract.balanceOf(f.user1.address)
        expect(userBalance).eq(mintAmount)
        // Confirm that the asset total supply increased as expected
        const kopioSupplyAfter = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyAfter.eq(kopioSupplyBefore.add(mintAmount)))
      })

      it('should allow successive, valid mints of the same kopios', async function () {
        // Mint assets
        const firstMintAmount = toBig(50)
        await f.User1.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: firstMintAmount, receiver: f.user1.address },
          hre.updateData(),
        )

        // Confirm the array of the user's minted assets has been pushed to.
        const mintedAssetsAfter = await hre.Diamond.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])

        // Confirm the amount minted is recorded for the user.
        const amountMintedAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
        expect(amountMintedAfter).eq(firstMintAmount)

        // Confirm the assets as been minted to the user from protocol
        const userBalanceAfter = await f.Kopio.contract.balanceOf(f.user1.address)
        expect(userBalanceAfter).eq(amountMintedAfter)

        // Confirm that the asset total supply increased as expected
        const kopioSupplyAfter = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyAfter).eq(f.initialMintAmount.add(firstMintAmount))

        // ------------------------ Second mint ------------------------
        // Mint assets
        const secondMintAmount = toBig(50)
        await f.User1.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: secondMintAmount, receiver: f.user1.address },
          hre.updateData(),
        )

        // Confirm the array of the user's minted assets is unchanged
        const mintedAssetsFinal = await hre.Diamond.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsFinal).to.deep.eq([f.Kopio.address])

        // Confirm the second mint amount is recorded for the user
        const amountMintedFinal = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
        expect(amountMintedFinal).eq(firstMintAmount.add(secondMintAmount))

        // Confirm the assets as been minted to the user from protocol
        const userBalanceFinal = await f.Kopio.contract.balanceOf(f.user1.address)
        expect(userBalanceFinal).eq(amountMintedFinal)

        // Confirm that the asset total supply increased as expected
        const kopioTotalSupplyFinal = await f.Kopio.contract.totalSupply()
        expect(kopioTotalSupplyFinal).eq(kopioSupplyAfter.add(secondMintAmount))
      })

      it('should allow users to mint multiple different assets', async function () {
        // Initially, the array of the user's minted assets should be empty.
        const mintedAssetsInitial = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsInitial).to.deep.eq([])

        // Mint assets
        const firstMintAmount = toBig(10)
        await f.User1.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: firstMintAmount, receiver: f.user1.address },
          hre.updateData(),
        )

        // Confirm the array of the user's minted assets has been pushed to.
        const mintedAssetsAfter = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])
        // Confirm the amount minted is recorded for the user.
        const amountMintedAfter = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(amountMintedAfter).eq(firstMintAmount)
        // Confirm the assets as been minted to the user from protocol
        const userBalanceAfter = await f.Kopio.balanceOf(f.user1.address)
        expect(userBalanceAfter).eq(amountMintedAfter)
        // Confirm that the asset total supply increased as expected
        const kopioSupplyAfter = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyAfter).eq(f.initialMintAmount.add(firstMintAmount))

        // ------------------------ Second mint ------------------------

        // Mint assets
        const secondMintAmount = toBig(20)
        await f.User1.mintKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio2.address,
            amount: secondMintAmount,
            receiver: f.user1.address,
          },
          hre.updateData(),
        )

        // Confirm that the second address has been pushed to the array of the user's minted assets
        const mintedAssetsFinal = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsFinal).to.deep.eq([f.Kopio.address, f.Kopio2.address])
        // Confirm the second mint amount is recorded for the user
        const amountMintedAssetTwo = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio2)
        expect(amountMintedAssetTwo).eq(secondMintAmount)
        // Confirm the assets as been minted to the user from protocol
        const userBalanceFinal = await f.Kopio2.balanceOf(f.user1.address)
        expect(userBalanceFinal).eq(amountMintedAssetTwo)
        // Confirm that the asset total supply increased as expected
        const secondKopioSupply = await f.Kopio2.contract.totalSupply()
        expect(secondKopioSupply).eq(secondMintAmount)
      })

      it('should allow users to mint assets with USD value equal to the minimum debt value', async function () {
        // Confirm that the mint amount's USD value is equal to the contract's current minimum debt value
        const mintAmount = toBig(1) // 1 * $10 = $10
        const mintAmountUSDValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)
        const currMinimumDebtValue = await hre.Diamond.getMinDebtValue()
        expect(mintAmountUSDValue).eq(currMinimumDebtValue)

        await f.User1.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
          hre.updateData(),
        )

        // Confirm that the mint was successful and user's balances have increased
        const finalAssetDebt = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(finalAssetDebt).eq(mintAmount)
      })

      it('should allow a trusted address to mint assets on behalf of another user', async function () {
        await hre.Diamond.grantRole(Role.MANAGER, f.user2.address)

        // Initially, the array of the user's minted assets should be empty.
        const mintedAssetsBefore = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsBefore).to.deep.eq([])

        // userThree (trusted contract) mints assets for userOne
        const mintAmount = toBig(1)
        await f.User2.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
          hre.updateData(),
        )

        // Check that debt exists now for userOne
        const userTwoBalanceAfter = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(userTwoBalanceAfter).eq(mintAmount)
        // Initially, the array of the user's minted assets should be empty.
        const mintedAssetsAfter = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])
      })

      it('should emit KopioMinted event', async function () {
        const tx = await f.User1.mintKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: f.initialMintAmount,
            receiver: f.user1.address,
          },
          hre.updateData(),
        )

        const event = await getInternalEvent<KopioMintedEventObject>(tx, hre.Diamond, 'KopioMinted')
        expect(event.account).eq(f.user1.address)
        expect(event.kopio).eq(f.Kopio.address)
        expect(event.amount).eq(f.initialMintAmount)
      })

      it('should not allow untrusted account to mint assets on behalf of another user', async function () {
        await expect(
          f.User1.mintKopio(
            { account: f.user2.address, kopio: f.Kopio.address, amount: toBig(1), receiver: f.user2.address },
            hre.updateData(),
          ),
        ).to.be.revertedWith(
          `AccessControl: account ${f.user1.address.toLowerCase()} is missing role 0x7c6cf2e8411c745b3e634d27b3f960faa6d22031873cce603a8e28a029c2b0e1`,
        )
      })

      it("should not allow users to mint assets if the resulting position's USD value is less than the minimum debt value", async function () {
        const currMinimumDebtValue = await optimized.getMinDebtValue()
        const mintAmount = currMinimumDebtValue.wadDiv(TEN_USD.ebn(8)).sub(1e9)

        await expect(
          f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          ),
        )
          .to.be.revertedWithCustomError(Errors(hre), 'MINT_VALUE_LESS_THAN_MIN_DEBT_VALUE')
          .withArgs(f.Kopio.errorId, 10e8 - 1, currMinimumDebtValue)
      })

      it('should not allow users to mint non-whitelisted assets', async function () {
        // Attempt to mint a non-deployed, non-whitelisted assets
        await expect(
          f.User1.mintKopio(
            {
              account: f.user1.address,
              kopio: '0x0000000000000000000000000000000000000002',
              amount: toBig(1),
              receiver: f.user1.address,
            },
            hre.updateData(),
          ),
        )
          .to.be.revertedWithCustomError(Errors(hre), 'NOT_MINTABLE')
          .withArgs(['', '0x0000000000000000000000000000000000000002'])
      })

      it('should not allow users to mint assets over their collateralization ratio limit', async function () {
        const collateralAmountDeposited = await optimized.getAccountCollateralAmount(
          f.user1.address,
          f.Collateral.address,
        )

        const MCR = await hre.Diamond.getMCR()
        const mcrAmount = collateralAmountDeposited.percentMul(MCR)
        const mintAmount = mcrAmount.add(1)
        const mintValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

        const userState = await hre.Diamond.getAccountState(f.user1.address)

        await expect(
          f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          ),
        )
          .to.be.revertedWithCustomError(Errors(hre), 'ACCOUNT_COLLATERAL_TOO_LOW')
          .withArgs(f.user1.address, userState.totalCollateralValue, mintValue.percentMul(MCR), MCR)
      })

      it('should not allow the minting of any assets amount over its maximum limit', async function () {
        // User deposits another 10,000 collateral tokens, enabling mints of up to 20,000/1.5 = ~13,333 asset tokens
        await f.Collateral.setBalance(f.user1, toBig(100000000))
        await expect(f.User1.depositCollateral(f.user1.address, f.Collateral.address, toBig(10000))).not.to.be.reverted
        const assetSupplyLimit = toBig(1)
        const mintAmount = toBig(2)
        await f.Kopio.update({
          mintLimit: assetSupplyLimit,
        })

        await expect(
          f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          ),
        )
          .to.be.revertedWithCustomError(Errors(hre), 'EXCEEDS_ASSET_MINTING_LIMIT')
          .withArgs(f.Kopio.errorId, (await f.Kopio.contract.totalSupply()).add(mintAmount), assetSupplyLimit)
        await f.Kopio.update({
          mintLimit: assetSupplyLimit,
        })
      })
      it.skip('should not allow the minting of kopios if the market is closed', async function () {
        await expect(
          f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: toBig(1), receiver: f.user1.address },
            hre.updateData(),
          ),
        ).to.be.revertedWithCustomError(Errors(hre), 'MARKET_CLOSED')

        // Confirm that the user has no minted kopios
        const mintedAssetsBefore = await hre.Diamond.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsBefore).to.deep.eq([])

        // Confirm that opening the market makes kopio mintable again
        await f.User1.mintKopio(
          { account: f.user1.address, kopio: f.Kopio.address, amount: toBig(10), receiver: f.user1.address },
          hre.updateData(),
        )

        // Confirm the array of the user's minted assets has been pushed to
        const mintedAssetsAfter = await hre.Diamond.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])
      })
    })

    describe('#mint - rebase', () => {
      const mintAmountDec = 40
      const mintAmount = toBig(mintAmountDec)
      describe('debt amounts are calculated correctly', () => {
        it('when minted before positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          const balanceBefore = await f.Kopio.balanceOf(f.user1.address)

          // Rebase the asset according to params
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure that the minted balance is adjusted by the rebase
          const [balanceAfter, balanceAfterAdjusted] = await getDebtIndexAdjustedBalance(f.user1, f.Kopio)
          expect(balanceAfter).eq(mintAmount.mul(denominator))
          expect(balanceBefore).not.eq(balanceAfter)

          // Ensure that debt amount is also adjsuted by the rebase
          const debtAmount = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          expect(balanceAfterAdjusted).eq(debtAmount)
        })

        it('when minted before negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          const balanceBefore = await f.Kopio.balanceOf(f.user1.address)

          // Rebase the asset according to params
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure that the minted balance is adjusted by the rebase
          const [balanceAfter, balanceAfterAdjusted] = await getDebtIndexAdjustedBalance(f.user1, f.Kopio)
          expect(balanceAfter).eq(mintAmount.div(denominator))
          expect(balanceBefore).not.eq(balanceAfter)

          // Ensure that debt amount is also adjsuted by the rebase
          const debtAmount = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          expect(balanceAfterAdjusted).eq(debtAmount)
        })

        it('when minted after positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          const balanceBefore = await f.Kopio.balanceOf(f.user1.address)

          // Rebase the asset according to params
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure that the minted balance is adjusted by the rebase
          const [balanceAfter, balanceAfterAdjusted] = await getDebtIndexAdjustedBalance(f.user1, f.Kopio)
          expect(balanceAfter).eq(mintAmount.mul(denominator))
          expect(balanceBefore).not.eq(balanceAfter)

          // Ensure that debt amount is also adjusted by the rebase
          const debtAmount = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          expect(balanceAfterAdjusted).eq(debtAmount)
        })

        it('when minted after negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          const balanceBefore = await f.Kopio.balanceOf(f.user1.address)

          // Rebase the asset according to params
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure that the minted balance is adjusted by the rebase
          const [balanceAfter, balanceAfterAdjusted] = await getDebtIndexAdjustedBalance(f.user1, f.Kopio)
          expect(balanceAfter).eq(mintAmount.div(denominator))
          expect(balanceBefore).not.eq(balanceAfter)

          // Ensure that debt amount is also adjusted by the rebase
          const debtAmount = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          expect(balanceAfterAdjusted).eq(debtAmount)
        })
      })

      describe('debt values are calculated correctly', () => {
        it('when mint is made before positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )
          const valueBeforeRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)

          // Adjust price accordingly
          const { pyth: assetPrice } = await f.Kopio.getPrice()
          await f.Kopio.setPrice(fromBig(assetPrice.div(denominator), 8))

          // Rebase the asset according to params
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure that the value inside protocol matches the value before rebase
          const valueAfterRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(valueAfterRebase).eq(valueBeforeRebase)
        })

        it('when mint is made before negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )
          const valueBeforeRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)

          // Adjust price accordingly
          const { pyth: assetPrice } = await f.Kopio.getPrice()
          await f.Kopio.setPrice(fromBig(assetPrice.mul(denominator), 8))

          // Rebase the asset according to params
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure that the value inside protocol matches the value before rebase
          const valueAfterRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(valueAfterRebase).eq(valueBeforeRebase)
        })
        it('when minted after positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true
          // Equal value after rebase
          const equalMintAmount = mintAmount.mul(denominator)

          const { pyth: assetPrice } = await f.Kopio.getPrice()

          // Get value of the future mint before rebase
          const valueBeforeRebase = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

          // Adjust price accordingly
          await f.Kopio.setPrice(fromBig(assetPrice, 8) / denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, '0x')

          await f.User1.mintKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: equalMintAmount,
              receiver: f.user1.address,
            },
            hre.updateData(),
          )

          // Ensure that value after mint matches what is expected
          const valueAfterRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(valueAfterRebase).eq(valueBeforeRebase)
        })

        it('when minted after negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false
          // Equal value after rebase
          const equalMintAmount = mintAmount.div(denominator)

          const { pyth: assetPrice } = await f.Kopio.getPrice()

          // Get value of the future mint before rebase
          const valueBeforeRebase = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

          // Adjust price accordingly
          await f.Kopio.setPrice(fromBig(assetPrice.mul(denominator), 8))
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          await f.User1.mintKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: equalMintAmount,
              receiver: f.user1.address,
            },
            hre.updateData(),
          )

          // Ensure that value after mint matches what is expected
          const valueAfterRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(valueAfterRebase).eq(valueBeforeRebase)
        })
      })

      describe('debt values and amounts are calculated correctly', () => {
        it('when minted before and after a positive rebase', async function () {
          const { pyth: assetPrice } = await f.Kopio.getPrice()

          // Rebase params
          const denominator = 4
          const positive = true

          const mintAmountAfterRebase = mintAmount.mul(denominator)
          const assetPriceRebase = assetPrice.div(denominator)

          // Get value of the future mint
          const valueBeforeRebase = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          // Get results
          const balanceAfterFirstMint = await f.Kopio.contract.balanceOf(f.user1.address)
          const debtAmountAfterFirstMint = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const debtValueAfterFirstMint = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)

          // Assert
          expect(balanceAfterFirstMint).eq(debtAmountAfterFirstMint)
          expect(valueBeforeRebase).eq(debtValueAfterFirstMint)

          // Adjust price and rebase
          await f.Kopio.setPrice(fromBig(assetPriceRebase, 8))
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure debt amounts and balances match
          const [balanceAfterFirstRebase, balanceAfterFirstRebaseAdjusted] = await getDebtIndexAdjustedBalance(
            f.user1,
            f.Kopio,
          )
          const debtAmountAfterFirstRebase = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          expect(balanceAfterFirstRebase).eq(mintAmountAfterRebase)
          expect(balanceAfterFirstRebaseAdjusted).eq(debtAmountAfterFirstRebase)

          // Ensure debt usd values match
          const debtValueAfterFirstRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(await fromScaledAmount(debtValueAfterFirstRebase, f.Kopio)).eq(debtValueAfterFirstMint)
          expect(await fromScaledAmount(debtValueAfterFirstRebase, f.Kopio)).eq(valueBeforeRebase)

          // Mint after rebase
          await f.User1.mintKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: mintAmountAfterRebase,
              receiver: f.user1.address,
            },
            hre.updateData(),
          )

          // Ensure debt amounts and balances match
          const balanceAfterSecondMint = await f.Kopio.contract.balanceOf(f.user1.address)

          // Ensure balance matches
          const expectedBalanceAfterSecondMint = balanceAfterFirstRebase.add(mintAmountAfterRebase)
          expect(balanceAfterSecondMint).eq(expectedBalanceAfterSecondMint)
          // Ensure debt usd values match
          const debtValueAfterSecondMint = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(await fromScaledAmount(debtValueAfterSecondMint, f.Kopio)).eq(debtValueAfterFirstMint.mul(2))
          expect(debtValueAfterSecondMint).eq(valueBeforeRebase.mul(2))
        })

        it('when minted before and after a negative rebase', async function () {
          const { pyth: assetPrice } = await f.Kopio.getPrice()

          // Rebase params
          const denominator = 4
          const positive = false

          const mintAmountAfterRebase = mintAmount.div(denominator)
          const assetPriceRebase = assetPrice.mul(denominator)

          // Get value of the future mint
          const valueBeforeRebase = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

          // Mint before rebase
          await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          // Get results
          const balanceAfterFirstMint = await f.Kopio.contract.balanceOf(f.user1.address)
          const debtAmountAfterFirstMint = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const debtValueAfterFirstMint = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)

          // Assert
          expect(balanceAfterFirstMint).eq(debtAmountAfterFirstMint)
          expect(valueBeforeRebase).eq(debtValueAfterFirstMint)

          // Adjust price and rebase
          await f.Kopio.setPrice(fromBig(assetPriceRebase, 8))
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Ensure debt amounts and balances match
          const [balanceAfterFirstRebase, balanceAfterFirstRebaseAdjusted] = await getDebtIndexAdjustedBalance(
            f.user1,
            f.Kopio,
          )
          const debtAmountAfterFirstRebase = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          expect(balanceAfterFirstRebase).eq(mintAmountAfterRebase)
          expect(balanceAfterFirstRebaseAdjusted).eq(debtAmountAfterFirstRebase)

          // Ensure debt usd values match
          const debtValueAfterFirstRebase = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(debtValueAfterFirstRebase).eq(await toScaledAmount(debtValueAfterFirstMint, f.Kopio))
          expect(debtValueAfterFirstRebase).eq(await toScaledAmount(valueBeforeRebase, f.Kopio))

          // Mint after rebase
          await f.User1.mintKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: mintAmountAfterRebase,
              receiver: f.user1.address,
            },
            hre.updateData(),
          )

          // Ensure debt usd values match
          const debtValueAfterSecondMint = await hre.Diamond.getAccountTotalDebtValue(f.user1.address)
          expect(debtValueAfterSecondMint).eq(await toScaledAmount(debtValueAfterFirstMint.mul(2), f.Kopio))
          expect(debtValueAfterSecondMint).eq(await toScaledAmount(valueBeforeRebase.mul(2), f.Kopio))
        })
      })
    })

    describe('#burn', () => {
      beforeEach(async function () {
        await f.User1.mintKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: f.initialMintAmount,
            receiver: f.user1.address,
          },
          hre.updateData(),
        )
      })

      it('should allow users to burn some of their assets balances', async function () {
        const kopioSupplyBefore = await f.Kopio.contract.totalSupply()

        // Burn assets
        const burnAmount = toBig(1)
        await f.User1.burnKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: burnAmount,
            repayee: f.user1.address,
          },
          hre.updateData(),
        )

        // Confirm the user no long holds the burned assets amount
        const userBalance = await f.Kopio.balanceOf(f.user1.address)
        expect(userBalance).eq(f.initialMintAmount.sub(burnAmount))

        // Confirm that the asset total supply decreased as expected
        const kopioSupplyAfter = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyAfter).eq(kopioSupplyBefore.sub(burnAmount))

        // Confirm the array of the user's minted assets still contains the asset's address
        const mintedAssetsAfter = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])

        // Confirm the user's minted asset amount has been updated
        const userDebt = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(userDebt).eq(f.initialMintAmount.sub(burnAmount))
      })

      it('should allow trusted address to burn its own assets balances on behalf of another user', async function () {
        await hre.Diamond.grantRole(Role.MANAGER, f.user2.address)

        const kopioSupplyBefore = await f.Kopio.contract.totalSupply()

        // Burn assets
        const burnAmount = toBig(1)
        const userOneBalanceBefore = await f.Kopio.balanceOf(f.user1.address)

        // User three burns it's assets to reduce userOnes debt
        await f.User2.burnKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: burnAmount,
            repayee: f.user2.address,
          },
          hre.updateData(),
        )
        //   .reverted;

        // Confirm the userOne had no effect on it's kopio balance
        const userOneBalance = await f.Kopio.balanceOf(f.user1.address)
        expect(userOneBalance).eq(userOneBalanceBefore, 'userOneBalance')

        // Confirm the userThree no long holds the burned assets amount
        const userThreeBalance = await f.Kopio.balanceOf(f.user2.address)
        expect(userThreeBalance).eq(f.initialMintAmount.sub(burnAmount), 'userThreeBalance')
        // Confirm that the asset total supply decreased as expected
        const kopioSupplyAfter = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyAfter).eq(kopioSupplyBefore.sub(burnAmount), 'totalSupplyAfter')
        // Confirm the array of the user's minted assets still contains the asset's address
        const mintedAssetsAfter = await optimized.getAccountMintedAssets(f.user2.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address], 'mintedAssetsAfter')
        // Confirm the user's minted asset amount has been updated
        const userOneDebt = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(userOneDebt).eq(f.initialMintAmount.sub(burnAmount))
      })

      it('should allow trusted address to burn the full balance of its assets on behalf another user')

      it('should burn up to the minimum debt position amount if the requested burn would result in a position under the minimum debt value', async function () {
        const userBalanceBefore = await f.Kopio.balanceOf(f.user1.address)
        const kopioSupplyBefore = await f.Kopio.contract.totalSupply()

        // Calculate actual burn amount
        const userOneDebt = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)

        const minDebtValue = fromBig(await optimized.getMinDebtValue(), 8)

        const oraclePrice = f.Kopio.config.args!.price
        const burnAmount = toBig(fromBig(userOneDebt) - minDebtValue / oraclePrice!)

        // Burn assets
        await f.User1.burnKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: burnAmount,
            repayee: f.user1.address,
          },
          hre.updateData(),
        )

        // Confirm the user holds the expected assets amount
        const userBalance = await f.Kopio.balanceOf(f.user1.address)

        // expect(fromBig(userBalance)).eq(fromBig(userBalanceBefore.sub(burnAmount)));
        expect(userBalance).eq(userBalanceBefore.sub(burnAmount))

        // Confirm that the asset total supply decreased as expected
        const kopioSupplyAfter = await f.Kopio.contract.totalSupply()
        expect(kopioSupplyAfter).eq(kopioSupplyBefore.sub(burnAmount))

        // Confirm the array of the user's minted assets still contains the asset's address
        const mintedAssetsAfter = await optimized.getAccountMintedAssets(f.user1.address)
        expect(mintedAssetsAfter).to.deep.eq([f.Kopio.address])

        // Confirm the user's minted asset amount has been updated
        const newUserDebt = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(newUserDebt).eq(userOneDebt.sub(burnAmount))
      })

      it('should emit KopioBurned event', async function () {
        const tx = await f.User1.burnKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: f.initialMintAmount.div(5),
            repayee: f.user1.address,
          },
          hre.updateData(),
        )

        const event = await getInternalEvent<KopioBurnedEventObject>(tx, hre.Diamond, 'KopioBurned')
        expect(event.account).eq(f.user1.address)
        expect(event.kopio).eq(f.Kopio.address)
        expect(event.amount).eq(f.initialMintAmount.div(5))
      })

      it('should allow users to burn assets without giving token approval to protocol contract', async function () {
        const secondMintAmount = 1
        const burnAmount = f.initialMintAmount.add(secondMintAmount)

        await expect(
          f.User1.mintKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: secondMintAmount,
              receiver: f.user1.address,
            },
            hre.updateData(),
          ),
        ).to.not.be.reverted

        await expect(
          f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: burnAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          ),
        ).to.not.be.reverted
      })

      it('should not allow users to burn an amount of 0', async function () {
        await expect(
          f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: 0,
              repayee: f.user1.address,
            },
            hre.updateData(),
          ),
        ).to.be.revertedWithCustomError(Errors(hre), 'ZERO_SHARES_FROM_ASSETS')
      })

      it('should not allow untrusted address to burn any assets on behalf of another user', async function () {
        await expect(
          f.User2.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: 100,
              repayee: f.user1.address,
            },
            hre.updateData(),
          ),
        ).to.be.revertedWith(
          `AccessControl: account ${f.user2.address.toLowerCase()} is missing role 0x7c6cf2e8411c745b3e634d27b3f960faa6d22031873cce603a8e28a029c2b0e1`,
        )
      })
      it('should not allow untrusted address to use another repayee to burn assets', async function () {
        await expect(
          f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: 100,
              repayee: f.user2.address,
            },
            hre.updateData(),
          ),
        ).to.be.revertedWith(
          `AccessControl: account ${f.user1.address.toLowerCase()} is missing role 0x7c6cf2e8411c745b3e634d27b3f960faa6d22031873cce603a8e28a029c2b0e1`,
        )
      })

      it('should not allow users to burn more assets than they hold as debt', async function () {
        const debt = await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)
        expect(debt).to.be.gt(0)
        const burnAmount = debt.add(toBig(10))

        await f.User1.burnKopio(
          {
            account: f.user1.address,
            kopio: f.Kopio.address,
            amount: burnAmount,
            repayee: f.user1.address,
          },
          hre.updateData(),
        )

        expect(await f.Kopio.balanceOf(f.user1.address)).eq(0)
        expect(await optimized.getAccountDebtAmount(f.user1.address, f.Kopio)).eq(0)
      })

      describe('Protocol open fee', () => {
        it('should charge the protocol open fee with a single collateral asset if the deposit amount is sufficient and emit FeePaid event', async function () {
          const openFee = 0.01e4

          await f.Kopio.update({
            openFee,
            mintLimit: MaxUint128,
          })
          const mintAmount = toBig(1)
          const mintValue = mintAmount.wadMul(TEN_USD.ebn(8))

          const expectedFeeValue = mintValue.percentMul(openFee)
          const expecetdCollFees = expectedFeeValue.wadDiv(TEN_USD.ebn(8))

          // Get the balances prior to the fee being charged.
          const feeRecipient = await hre.Diamond.getFeeRecipient()
          const protocolCollBalBefore = await f.Collateral.balanceOf(hre.Diamond.address)
          const recipientCollBalBefore = await f.Collateral.balanceOf(feeRecipient)

          // Mint assets
          const tx = await f.User1.mintKopio(
            { account: f.user1.address, kopio: f.Kopio.address, amount: mintAmount, receiver: f.user1.address },
            hre.updateData(),
          )

          // Get the balances after the fees have been charged.
          const protocolCollBalAfter = await f.Collateral.balanceOf(hre.Diamond.address)
          const recipientCollBalAfter = await f.Collateral.balanceOf(feeRecipient)

          // Ensure the amount gained / lost by the protocol contract and the fee recipient are as expected
          const recipientBalIncrese = recipientCollBalAfter.sub(recipientCollBalBefore)
          expect(protocolCollBalBefore.sub(protocolCollBalAfter)).eq(recipientBalIncrese)

          // Normalize expected amount because protocol closeFee has 10**18 decimals
          expect(recipientBalIncrese).eq(expecetdCollFees)

          // Ensure the emitted event is as expected.
          const event = await getInternalEvent<FeePaidEventObject>(tx, hre.Diamond, 'FeePaid')
          expect(event.account).eq(f.user1.address)
          expect(event.collateral).eq(f.Collateral.address)
          expect(event.amount).eq(expecetdCollFees)

          expect(event.value).eq(expectedFeeValue)
          expect(event.feeType).eq(ICDPFee.OPEN)

          // Now verify that calcExpectedFee function returns accurate fee amount
          const [, values] = await hre.Diamond.previewFee(f.user1.address, f.Kopio.address, mintAmount, ICDPFee.OPEN)
          expect(values[0]).eq(expecetdCollFees)
        })
      })
      describe('Protocol Close Fee', () => {
        it('should charge the protocol close fee with a single collateral asset if the deposit amount is sufficient and emit FeePaid event', async function () {
          const burnAmount = toBig(1)
          const burnValue = burnAmount.wadMul(TEN_USD.ebn(8))
          const closeFee = f.Kopio.config.args.kopioConfig!.closeFee // use toBig() to emulate closeFee's 18 decimals on contract
          const expectedFeeValue = burnValue.percentMul(closeFee)
          const expecetdCollFees = expectedFeeValue.wadDiv(f.Collateral.config.args!.price!.ebn(8))
          const feeRecipient = await hre.Diamond.getFeeRecipient()
          // Get the balances prior to the fee being charged.
          const protocolCollBalBefore = await f.Collateral.balanceOf(hre.Diamond.address)
          const recipientCollBalBefore = await f.Collateral.balanceOf(feeRecipient)

          // Burn assets
          const tx = await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: burnAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Get the balances after the fees have been charged.
          const protocolCollBalAfter = await f.Collateral.balanceOf(hre.Diamond.address)
          const recipientCollBalAfter = await f.Collateral.balanceOf(feeRecipient)

          // Ensure the amount gained / lost by the protocol contract and the fee recipient are as expected
          const recipientBalIncrese = recipientCollBalAfter.sub(recipientCollBalBefore)
          expect(protocolCollBalBefore.sub(protocolCollBalAfter)).eq(recipientBalIncrese)

          // Normalize expected amount because protocol closeFee has 10**18 decimals
          expect(recipientBalIncrese).eq(expecetdCollFees)

          // Ensure the emitted event is as expected.
          const event = await getInternalEvent<FeePaidEventObject>(tx, hre.Diamond, 'FeePaid')
          expect(event.account).eq(f.user1.address)
          expect(event.collateral).eq(f.Collateral.address)
          expect(event.amount).eq(expecetdCollFees)
          expect(event.value).eq(expectedFeeValue)
          expect(event.feeType).eq(ICDPFee.CLOSE)
        })

        it('should charge correct protocol close fee after a positive rebase', async function () {
          const wAmount = 1
          const burnAmount = toBig(1)
          const expectedFeeAmount = burnAmount.percentMul(f.Kopio.config.args.kopioConfig!.closeFee)
          const expectedFeeValue = expectedFeeAmount.wadMul(toBig(TEN_USD, 8))

          const event = await getInternalEvent<FeePaidEventObject>(
            await burnKopio({
              user: f.user2,
              asset: f.Kopio,
              amount: burnAmount,
            }),
            hre.Diamond,
            'FeePaid',
          )

          expect(event.amount).eq(expectedFeeAmount)
          expect(event.value).eq(expectedFeeValue)
          expect(event.feeType).eq(ICDPFee.CLOSE)

          // rebase params
          const denominator = 4
          const positive = true
          await f.Kopio.setPrice(TEN_USD / denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])
          const burnAmountRebase = burnAmount.mul(denominator)

          await withdrawCollateral(
            {
              user: f.user2,
              asset: f.Collateral,
              amount: toBig(wAmount),
            },
            hre.updateData(),
          )
          const eventAfterRebase = await getInternalEvent<FeePaidEventObject>(
            await burnKopio({
              user: f.user2,
              asset: f.Kopio,
              amount: burnAmountRebase,
            }),
            hre.Diamond,
            'FeePaid',
          )
          expect(eventAfterRebase.collateral).eq(event.collateral)
          expect(eventAfterRebase.amount).eq(expectedFeeAmount)
          expect(eventAfterRebase.value).eq(expectedFeeValue)
        })
        it('should charge correct protocol close fee after a negative rebase', async function () {
          const wAmount = 1
          const burnAmount = toBig(1)
          const expectedFeeAmount = burnAmount.percentMul(f.Kopio.config.args.kopioConfig!.closeFee)
          const expectedFeeValue = expectedFeeAmount.wadMul(toBig(TEN_USD, 8))

          const event = await getInternalEvent<FeePaidEventObject>(
            await burnKopio({
              user: f.user2,
              asset: f.Kopio,
              amount: burnAmount,
            }),
            hre.Diamond,
            'FeePaid',
          )

          expect(event.amount).eq(expectedFeeAmount)
          expect(event.value).eq(expectedFeeValue)
          expect(event.feeType).eq(ICDPFee.CLOSE)

          // rebase params
          const denominator = 4
          const positive = false
          const priceAfter = fromBig((await f.Kopio.getPrice()).pyth, 8) * denominator
          await f.Kopio.setPrice(priceAfter)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])
          const burnAmountRebase = burnAmount.div(denominator)

          await withdrawCollateral(
            {
              user: f.user2,
              asset: f.Collateral,
              amount: toBig(wAmount),
            },
            hre.updateData(),
          )
          const eventAfterRebase = await getInternalEvent<FeePaidEventObject>(
            await burnKopio({
              user: f.user2,
              asset: f.Kopio,
              amount: burnAmountRebase,
            }),
            hre.Diamond,
            'FeePaid',
          )
          expect(eventAfterRebase.collateral).eq(event.collateral)
          expect(eventAfterRebase.amount).eq(expectedFeeAmount)
          expect(eventAfterRebase.value).eq(expectedFeeValue)
        })
      })
    })

    describe('#burn - rebase', () => {
      const mintAmountDec = 40
      const mintAmount = toBig(mintAmountDec)

      beforeEach(async function () {
        await mintKopio({
          asset: f.Kopio,
          amount: mintAmount,
          user: f.user1,
        })
      })

      describe('debt amounts are calculated correctly', () => {
        it('when repaying all debt after a positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD / denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Pay half of debt
          const debt = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const repayAmount = debt
          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: repayAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)

          expect(debtAfter).eq(0)

          const balanceAfterBurn = await f.Kopio.contract.balanceOf(f.user1.address)
          expect(balanceAfterBurn).eq(0)

          // Share kopios should equal balance * denominator
          const sharesProtocol = await f.Kopio.share!.balanceOf(hre.Diamond.address)
          expect(sharesProtocol).eq(f.initialMintAmount) // WEI
        })

        it('when repaying partial debt after a positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD / denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Pay half of debt
          const debt = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const repayAmount = debt.div(2)
          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: repayAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)

          // Calc expected value with last update
          const expectedDebt = mintAmount.div(2).mul(denominator)

          expect(debtAfter).eq(expectedDebt)

          // Should be all burned
          const expectedBalanceAfter = mintAmount.mul(denominator).sub(repayAmount)
          const balanceAfterBurn = await f.Kopio.contract.balanceOf(f.user1.address)
          expect(balanceAfterBurn).eq(expectedBalanceAfter)

          // All wkopios should be burned
          const expectedShareBal = mintAmount.sub(repayAmount.div(denominator)).add(f.initialMintAmount)
          const sharesProtocol = await f.Kopio.share!.balanceOf(hre.Diamond.address)
          expect(sharesProtocol).eq(expectedShareBal)
        })

        it('when repaying all debt after a negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD * denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Pay half of debt
          const debt = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const repayAmount = debt
          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: repayAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)

          // Calc expected value with last update
          const expectedDebt = 0

          expect(debtAfter).eq(expectedDebt)

          const expectedBalanceAfterBurn = 0
          const balanceAfterBurn = fromBig(await f.Kopio.contract.balanceOf(f.user1.address))
          expect(balanceAfterBurn).eq(expectedBalanceAfterBurn)

          // Share kopios should equal balance * denominator
          const sharesProtocol = await f.Kopio.share!.balanceOf(hre.Diamond.address)
          expect(sharesProtocol).eq(toBig(expectedBalanceAfterBurn * denominator).add(f.initialMintAmount))
        })

        it('when repaying partial debt after a negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD * denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Pay half of debt
          const debt = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const repayAmount = debt.div(2)
          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: repayAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)

          // Calc expected value with last update
          const expectedDebt = mintAmount.div(2).div(denominator)

          expect(debtAfter).eq(expectedDebt)

          // Should be all burned
          const expectedBalanceAfter = mintAmount.div(denominator).sub(repayAmount)
          const balanceAfterBurn = await f.Kopio.contract.balanceOf(f.user1.address)
          expect(balanceAfterBurn).eq(expectedBalanceAfter)

          // All wkopios should be burned
          const expectedShareBal = mintAmount.sub(repayAmount.mul(denominator)).add(f.initialMintAmount)
          const sharesProtocol = await f.Kopio.share.balanceOf(hre.Diamond.address)
          expect(sharesProtocol).eq(expectedShareBal)
        })
      })

      describe('debt value and mints book-keeping is calculated correctly', () => {
        it('when repaying all debt after a positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true
          const fullRepayAmount = mintAmount.mul(denominator)

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD / denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: fullRepayAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const debtValueAfter = await hre.Diamond.getValue(f.Kopio.address, debtAfter)
          expect(debtValueAfter).eq(0)
        })
        it('when repaying partial debt after a positive rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = true
          const mintValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD / denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])
          // Should contain minted kopio
          expect(await optimized.getAccountMintedAssets(f.user1.address)).to.include(f.Kopio.address)

          // Burn assets
          // Pay half of debt
          const debt = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: debt.div(2),
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const debtValueAfter = await hre.Diamond.getValue(f.Kopio.address, debtAfter)
          // Calc expected value with last update
          const expectedValue = mintValue.div(2)
          expect(debtValueAfter).eq(expectedValue)

          // Should still contain minted kopio
          expect(await f.User1.getAccountMintedAssets(f.user1.address)).to.contain(f.Kopio.address)
        })
        it('when repaying all debt after a negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false
          const fullRepayAmount = mintAmount.div(denominator)

          // Adjust price according to rebase params
          await f.Kopio.setPrice(TEN_USD * denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: fullRepayAmount,
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const debtValueAfter = await hre.Diamond.getValue(f.Kopio.address, debtAfter)
          expect(debtValueAfter).eq(0)
        })
        it('when repaying partial debt after a negative rebase', async function () {
          // Rebase params
          const denominator = 4
          const positive = false
          const mintValue = await hre.Diamond.getValue(f.Kopio.address, mintAmount)

          await f.Kopio.setPrice(TEN_USD * denominator)
          await f.Kopio.contract.rebase(toBig(denominator), positive, [])

          // Pay half of debt
          const debt = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          await f.User1.burnKopio(
            {
              account: f.user1.address,
              kopio: f.Kopio.address,
              amount: debt.div(2),
              repayee: f.user1.address,
            },
            hre.updateData(),
          )

          // Debt value after half repayment
          const debtAfter = await hre.Diamond.getAccountDebtAmount(f.user1.address, f.Kopio.address)
          const debtValueAfter = await hre.Diamond.getValue(f.Kopio.address, debtAfter)
          // Calc expected value with last update
          const expectedValue = mintValue.div(2)
          expect(debtValueAfter).eq(expectedValue)

          // Should still contain minted kopio
          const mintedAssetsAfterBurn = await hre.Diamond.getAccountMintedAssets(f.user1.address)
          expect(mintedAssetsAfterBurn).to.contain(f.Kopio.address)
        })
      })
    })
  })
})
