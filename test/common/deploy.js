const Presale = artifacts.require('PresaleMock.sol')
const FundraisingController = artifacts.require('FundraisingMock.sol')
const MiniMeToken = artifacts.require('@aragon/apps-shared-minime/contracts/MiniMeToken')
const TokenManager = artifacts.require('TokenManager.sol')
const Vault = artifacts.require('Vault.sol')
const Pool = artifacts.require('Pool.sol')
const DAOFactory = artifacts.require('@aragon/core/contracts/factory/DAOFactory')
const EVMScriptRegistryFactory = artifacts.require('@aragon/core/contracts/factory/EVMScriptRegistryFactory')
const ACL = artifacts.require('@aragon/core/contracts/acl/ACL')
const Kernel = artifacts.require('@aragon/core/contracts/kernel/Kernel')
const ERC20 = artifacts.require('@aragon/core/contracts/lib/token/ERC20')
const getContract = name => artifacts.require(name)
const { hash } = require('eth-ens-namehash')

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

  getProxyAddress: (receipt) => receipt.logs.filter(l => l.event === 'NewAppProxy')[0].args.proxy,

  /* DAO Factory */
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

  /* DAO */
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

  /* POOL */
  deployPool: async (test, appManager) => {
    const appBase = await Pool.new()
    const receipt = await test.dao.newAppInstance(hash('pool.aragonpm.eth'), appBase.address, '0x', false, { from: appManager })
    test.pool = Pool.at(deploy.getProxyAddress(receipt))

    await test.pool.initialize()
  },

  /* VAULT */
  deployVault: async (test, appManager) => {
    const appBase = await Vault.new()
    const receipt = await test.dao.newAppInstance(hash('vault.aragonpm.eth'), appBase.address, '0x', false, { from: appManager })
    test.vault = Vault.at(deploy.getProxyAddress(receipt))

    await test.vault.initialize()
  },

  /* TOKEN MANAGER */
  deployTokenManager: async (test, appManager) => {
    const appBase = await TokenManager.new()
    const receipt = await test.dao.newAppInstance(hash('token-manager.aragonpm.eth'), appBase.address, '0x', false, { from: appManager })
    test.tokenManager = TokenManager.at(deploy.getProxyAddress(receipt))

    const ISSUE_ROLE = await appBase.ISSUE_ROLE()
    const ASSIGN_ROLE = await appBase.ASSIGN_ROLE()
    const REVOKE_VESTINGS_ROLE = await appBase.REVOKE_VESTINGS_ROLE()
    const BURN_ROLE = await appBase.BURN_ROLE()
    await test.acl.createPermission(ANY_ADDRESS, test.tokenManager.address, BURN_ROLE, appManager, { from: appManager })
    await test.acl.createPermission(ANY_ADDRESS, test.tokenManager.address, REVOKE_VESTINGS_ROLE, appManager, { from: appManager })
    await test.acl.createPermission(ANY_ADDRESS, test.tokenManager.address, ISSUE_ROLE, appManager, { from: appManager })
    await test.acl.createPermission(ANY_ADDRESS, test.tokenManager.address, ASSIGN_ROLE, appManager, { from: appManager })

    await test.projectToken.changeController(test.tokenManager.address)
    await test.tokenManager.initialize(
      test.projectToken.address,
      true, /* transferable */
      0 /* macAccountTokens (infinite if set to 0) */
    )
  },

  /* PRESALE */
  deployApp: async (test, appManager) => {
    const appBase = await Presale.new()
    const receipt = await test.dao.newAppInstance(hash('presale.aragonpm.eth'), appBase.address, '0x', false, { from: appManager })
    test.presale = Presale.at(deploy.getProxyAddress(receipt))

    const START_ROLE = await appBase.START_ROLE()
    const BUY_ROLE = await appBase.BUY_ROLE()
    await test.acl.createPermission(appManager, test.presale.address, START_ROLE, appManager, { from: appManager })
    await test.acl.createPermission(ANY_ADDRESS, test.presale.address, BUY_ROLE, appManager, { from: appManager })

    await test.presale.initialize(
      test.daiToken.address,
      test.projectToken.address,
      test.tokenManager.address,
      VESTING_CLIFF_DATE,
      VESTING_COMPLETE_DATE,
      DAI_FUNDING_GOAL,
      PERCENT_SUPPLY_OFFERED,
      FUNDING_PERIOD,
      test.pool.address,
      test.fundraising.address,
      TAP_RATE
    )
  },

  /* TOKENS */
  deployTokens: async (test) => {
    test.daiToken = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'DaiToken', 18, 'DAI', true)
    test.projectToken = await MiniMeToken.new(ZERO_ADDRESS, ZERO_ADDRESS, 0, 'ProjectToken', 18, 'PRO', true)
  },

  /* FUNDRAISING */
  deployFundraisingController: async (test) => {
    test.fundraising = await FundraisingController.new()
  },

  /* ~EVERYTHING~ */
  deployDefaultSetup: async (test, appManager) => {
    await deploy.deployDAOFactory(test)
    await deploy.deployDAO(test, appManager)
    await deploy.deployTokens(test)
    await deploy.deployTokenManager(test, appManager)
    await deploy.deployVault(test, appManager)
    await deploy.deployPool(test, appManager)
    await deploy.deployFundraisingController(test)
    await deploy.deployApp(test, appManager)
  }
}

module.exports = deploy
