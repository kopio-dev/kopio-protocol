import { SmockFacet2__factory, SmockFacet__factory, type SmockInit__factory } from '@/types/typechain'
import { smock } from '@defi-wonderland/smock'
import { addFacet } from '@scripts/add-facet'
import { removeFacet } from '@scripts/remove-facet'
import { expect } from '@test/chai'
import { diamondFixture } from '@utils/test/fixtures'
import { type FacetCut, FacetCutAction } from 'hardhat-deploy/dist/types'

describe('Diamond', () => {
  beforeEach(async function () {
    await diamondFixture()
  })

  describe('#upgrades', () => {
    it('can add a new facet', async function () {
      const Factory = await smock.mock<SmockFacet__factory>('SmockFacet')
      const SmockFacet = await Factory.deploy()

      const [SmockInitializer] = await hre.deploy('SmockInit')

      const signatures = hre.getSignatures([...SmockFacet__factory.abi])

      const Cut: FacetCut = {
        facetAddress: SmockFacet.address,
        functionSelectors: signatures,
        action: FacetCutAction.Add,
      }

      const initData = await SmockInitializer.populateTransaction.initialize(hre.addr.userOne)

      await hre.Diamond.diamondCut([Cut], initData.to!, initData.data!)
      const TEST_OPERATOR_ROLE = hre.ethers.utils.id('kopio.test.operator')
      const isTestOperator = await hre.Diamond.hasRole(TEST_OPERATOR_ROLE, hre.addr.userOne)

      // Succesfully added the new operator through the initialization contract
      expect(isTestOperator).eq(true)

      const Facet = await hre.ethers.getContractAt([...SmockFacet__factory.abi], hre.Diamond.address)

      // Ensure facet has it's own storage
      const operatorFromNewStorage = await Facet.operator() // Retrieved from SmockStorage
      expect(operatorFromNewStorage).eq(hre.addr.userOne)
    })

    it('can remove a facet', async function () {
      const NewFacet = await addFacet({
        name: 'SmockFacet',
        initializerName: 'SmockInit',
        initializerArgs: hre.addr.userOne,
      })
      const facetsBefore = await hre.Diamond.facets()
      expect(facetsBefore.filter(f => f.facetAddress === NewFacet.address).length).eq(1)

      await removeFacet({ name: 'SmockFacet' })
      const facetsAfter = await hre.Diamond.facets()

      expect(facetsBefore.length - facetsAfter.length).eq(1)
      expect(facetsAfter).to.not.deep.contain(NewFacet.address)
    })

    it('can remove a function', async function () {
      // Delete acceptOwnership from DiamondStateFacet

      // Check there is no pending owner
      let pendingOwner = await hre.Diamond.pendingOwner()
      expect(pendingOwner).eq(hre.ethers.constants.AddressZero)

      // Transfer to eg. wrong address
      const wrongOwner = hre.addr.notAdmin
      await hre.Diamond.transferOwnership(wrongOwner)

      // Ensure
      pendingOwner = await hre.Diamond.pendingOwner()
      expect(pendingOwner).eq(wrongOwner)

      // Fragment and signature for acceptOwnersip
      const functionFragment = hre.Diamond.interface.functions['acceptOwnership()']
      const signature = hre.ethers.utils.Interface.getSighash(functionFragment)

      const facetAddress = await hre.Diamond.facetAddress(signature)
      const functions = await hre.Diamond.facetFunctionSelectors(facetAddress)

      const Cut: FacetCut = {
        facetAddress: hre.ethers.constants.AddressZero,
        action: FacetCutAction.Remove,
        functionSelectors: [signature],
      }

      // We will set a correct owner with delegatecall into the Diamond itself with the cut transaction
      const correctOwner = hre.addr.userOne
      const initData = await hre.Diamond.populateTransaction.transferOwnership(correctOwner)

      await hre.Diamond.diamondCut([Cut], initData.to!, initData.data!)

      // Ensure rest of the functions remain
      const functionsAfterCut = await hre.Diamond.facetFunctionSelectors(facetAddress)
      expect(functionsAfterCut.length).eq(functions.length - 1)

      // Ensure delegatecall did set the correct pending owner with the cut

      const contract = await hre.ethers.getContractAt('KopioCore', hre.Diamond.address)

      const filter = contract.filters.PendingOwnershipTransfer(hre.addr.deployer, correctOwner)
      const [event] = await contract.queryFilter(filter)
      const { previousOwner, newOwner } = event.args
      expect(previousOwner).eq(hre.addr.deployer)
      expect(newOwner).eq(correctOwner)

      // Ensure there is no function to accept the ownership
      await expect(hre.Diamond.connect(hre.users.notAdmin).acceptOwnership()).to.be.reverted
    })

    it('can replace a function', async function () {
      // Same as above but instead replace the function
      // Check there is no pending owner
      let pendingOwner = await hre.Diamond.pendingOwner()
      expect(pendingOwner).eq(hre.ethers.constants.AddressZero)

      // Transfer to eg. wrong address
      const wrongOwner = hre.addr.notAdmin
      await hre.Diamond.transferOwnership(wrongOwner)

      // Ensure
      pendingOwner = await hre.Diamond.pendingOwner()
      expect(pendingOwner).eq(wrongOwner)

      // Fragment and signature for acceptOwnersip
      const functionFragment = hre.Diamond.interface.functions['acceptOwnership()']
      const signature = hre.ethers.utils.Interface.getSighash(functionFragment)

      const OldOwnershipFacet = await hre.Diamond.facetAddress(signature)

      const [NewOwnershipFacet, allOwnershipFacetSignatures] = await hre.deploy('DiamondStateFacet', {
        deploymentName: 'DiamondStateFacet2',
      })

      // Only replace a single function, we could replace all of them
      const Cut: FacetCut = {
        facetAddress: NewOwnershipFacet.address,
        action: FacetCutAction.Replace,
        functionSelectors: [signature],
      }

      // We will set a correct owner with delegatecall into the Diamond itself with the cut transaction
      const correctOwner = hre.addr.userOne
      const initData = await hre.Diamond.populateTransaction.transferOwnership(correctOwner)

      await hre.Diamond.diamondCut([Cut], initData.to!, initData.data!)

      // Ensure function exists and revert is for invalid address instead of missing function
      await expect(hre.Diamond.connect(hre.users.notAdmin).acceptOwnership()).to.be.reverted
      // Ensure one function is contained in the new facet
      const functionsNewFacet = await hre.Diamond.facetFunctionSelectors(NewOwnershipFacet.address)
      expect(functionsNewFacet.length).eq(1)
      expect(functionsNewFacet).to.have.members([signature])

      // Ensure rest are in the previous one
      const functionsOldFacet = await hre.Diamond.facetFunctionSelectors(OldOwnershipFacet)
      expect(functionsOldFacet).to.not.have.members([signature])
      expect(functionsOldFacet.length).eq(allOwnershipFacetSignatures.length - 1)

      // Ensure correct owner can now accept the ownership
      expect(hre.Diamond.connect(hre.users.userOne).acceptOwnership())
      const currentOwner = await hre.Diamond.owner()
      expect(currentOwner).eq(correctOwner)
    })

    it('can upgrade state', async function () {
      expect(await hre.Diamond.initialized()).eq(true)

      const Factory = await smock.mock<SmockInit__factory>('SmockInit')
      const SmockInit = await Factory.deploy()

      const tx = await SmockInit.populateTransaction.upgradeState()

      await hre.Diamond.executeInitializer(tx.to!, tx.data!)
      expect(await hre.Diamond.initialized()).eq(false)
    })

    it('can preserve old state when extending storage layout', async function () {
      expect(await hre.Diamond.initialized()).eq(true)

      // Add the first facet
      const Factory = await smock.mock<SmockFacet__factory>('SmockFacet')
      const SmockFacet = await Factory.deploy()

      const [SmockInitializer] = await hre.deploy('SmockInit')

      const signatures = hre.getSignatures([...SmockFacet__factory.abi])

      const Cut: FacetCut = {
        facetAddress: SmockFacet.address,
        functionSelectors: signatures,
        action: FacetCutAction.Add,
      }

      const initData = await SmockInitializer.populateTransaction.initialize(hre.addr.userOne)
      await hre.Diamond.diamondCut([Cut], initData.to!, initData.data!)

      const Diamond = await hre.ethers.getContractAt('SmockFacet', hre.Diamond.address)
      const isInitialized = await Diamond.smockInitialized()
      expect(isInitialized).eq(true)

      // Add facet with extended state
      // Add the first facet
      const Factory2 = await smock.mock<SmockFacet2__factory>('SmockFacet2')
      const SmockFacet2 = await Factory2.deploy()

      const signatures2 = hre.getSignatures([...SmockFacet2__factory.abi])

      const Cut2: FacetCut = {
        facetAddress: SmockFacet2.address,
        functionSelectors: signatures2,
        action: FacetCutAction.Add,
      }

      // Initializer only sets the new extended value, does not touch old storage
      const initData2 = await SmockFacet2.populateTransaction.initialize()
      await hre.Diamond.diamondCut([Cut2], initData2.to!, initData2.data!)

      // Here we have appended the storage layout with the `extended` bool property.
      const DiamondExtended = await hre.ethers.getContractAt('SmockFacet2', hre.Diamond.address)

      const initializedAfterExtend = await DiamondExtended.getOldStructValueFromExtended()

      const extendedValue = await DiamondExtended.getNewStructValueFromExtended()

      // Old values remain
      expect(initializedAfterExtend).eq(true)
      // And we get new ones
      expect(extendedValue).eq(true)
    })
  })
})
