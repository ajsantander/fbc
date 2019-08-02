const Presale = artifacts.require('PresaleMock.sol')
const FundraisingController = artifacts.require('FundraisingMock.sol')
const MiniMeToken = artifacts.require('@aragon/apps-shared-minime/contracts/MiniMeToken')
const TokenManager = artifacts.require('TokenManager.sol')
const DAOFactory = artifacts.require('@aragon/core/contracts/factory/DAOFactory')
const EVMScriptRegistryFactory = artifacts.require('@aragon/core/contracts/factory/EVMScriptRegistryFactory')
const ACL = artifacts.require('@aragon/core/contracts/acl/ACL')
const Kernel = artifacts.require('@aragon/core/contracts/kernel/Kernel')
const ERC20 = artifacts.require('@aragon/core/contracts/lib/token/ERC20')
const getContract = name => artifacts.require(name)

const {
  ANY_ADDRESS,
  ZERO_ADDRESS,
  VESTING_CLIFF_DATE,
  VESTING_COMPLETE_DATE,
  DAI_FUNDING_GOAL,
  PERCENT_SUPPLY_OFFERED,
  FUNDING_PERIOD,
  TAP_RATE
} = require('./constants')

const deploy = {

  deployDAOFactory: async (test) => {
    const kernelBase = await getContract('Kernel').new(true) // petrify immediately
    const aclBase = await getContract('ACL').new()
    const regFact = await EVMScriptRegistryFactory.new()
    test.daoFact = await DAOFactory.new(
      kernelBase.address,
      aclBase.address,
      regFact.address
    )
    test.APP_MANAGER_ROLE = await kernelBase.APP_MANAGER_ROLE()
  },

  deployDAO: async (test, daoManager) => {

    const daoReceipt = await test.daoFact.newDAO(daoManager)
    test.dao = Kernel.at(
      daoReceipt.logs.filter(l => l.event === 'DeployDAO')[0].args.dao
    )

    test.acl = ACL.at(await test.dao.acl())

    await test.acl.createPermission(
      daoManager,
      test.dao.address,
      test.APP_MANAGER_ROLE,
      daoManager,
      { from: daoManager }
    )
  },

  deployTokenManager: async (test, appManager) => {

    const appBase = await TokenManager.new()
    test.ISSUE_ROLE = await appBase.ISSUE_ROLE()
    test.ASSIGN_ROLE = await appBase.ASSIGN_ROLE()
    test.REVOKE_VESTINGS_ROLE = await appBase.REVOKE_VESTINGS_ROLE()
    test.BURN_ROLE = await appBase.BURN_ROLE()

    const daoInstanceReceipt = await test.dao.newAppInstance(
      '0x123',
      appBase.address,
      '0x',
      false,
      { from: appManager }
    )

    const proxy = daoInstanceReceipt.logs.filter(l => l.event === 'NewAppProxy')[0].args.proxy
    test.tokenManager = TokenManager.at(proxy)

    await test.acl.createPermission(
      ANY_ADDRESS,
      test.tokenManager.address,
      test.BURN_ROLE,
      appManager,
      { from: appManager }
    )
    await test.acl.createPermission(
      ANY_ADDRESS,
      test.tokenManager.address,
      test.REVOKE_VESTINGS_ROLE,
      appManager,
      { from: appManager }
    )
    await test.acl.createPermission(
      ANY_ADDRESS,
      test.tokenManager.address,
      test.ISSUE_ROLE,
      appManager,
      { from: appManager }
    )
    await test.acl.createPermission(
      ANY_ADDRESS,
      test.tokenManager.address,
      test.ASSIGN_ROLE,
      appManager,
      { from: appManager }
    )
  },

  deployApp: async (test, appManager) => {

    const appBase = await Presale.new()
    test.START_ROLE = await appBase.START_ROLE()
    test.BUY_ROLE = await appBase.BUY_ROLE()

    const daoInstanceReceipt = await test.dao.newAppInstance(
      '0x1234',
      appBase.address,
      '0x',
      false,
      { from: appManager }
    )

    const proxy = daoInstanceReceipt.logs.filter(l => l.event === 'NewAppProxy')[0].args.proxy
    test.app = Presale.at(proxy)

    await test.acl.createPermission(
      appManager,
      test.app.address,
      test.START_ROLE,
      appManager,
      { from: appManager }
    )
    await test.acl.createPermission(
      ANY_ADDRESS,
      test.app.address,
      test.BUY_ROLE,
      appManager,
      { from: appManager }
    )
  },

  deployTokens: async (test) => {
    test.daiToken = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'DaiToken', 18, 'DAI', true)
    test.projectToken = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'ProjectToken', 18, 'PRO', true)
  },

  deployFundraisingController: async (test) => {
    test.fundraisingController = await FundraisingController.new()
  },

  deployDefaultSetup: async (test, managerAddress) => {

    // Deploy DAO.
    await deploy.deployDAOFactory(test)
    await deploy.deployDAO(test, managerAddress)

    // Deploy tokens and TokenManager.
    await deploy.deployTokens(test)
    await deploy.deployTokenManager(test, managerAddress)
    await test.projectToken.changeController(test.tokenManager.address)
    await test.tokenManager.initialize(
      test.projectToken.address,
      true, /* transferable */
      0 /* macAccountTokens (infinite if set to 0) */
    )

    // Deploy Fundraising app (dummy for now).
    await deploy.deployFundraisingController(test)

    // Deploy the Presale app.
    await deploy.deployApp(test, managerAddress)
    await test.app.initialize(
      test.daiToken.address,
      test.projectToken.address,
      test.tokenManager.address,
      VESTING_CLIFF_DATE,
      VESTING_COMPLETE_DATE,
      DAI_FUNDING_GOAL,
      PERCENT_SUPPLY_OFFERED,
      FUNDING_PERIOD,
      managerAddress, /* fundraisingPool */
      test.fundraisingController.address,
      TAP_RATE
    )
  }
}

module.exports = deploy
