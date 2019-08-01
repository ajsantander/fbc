const Prefunding = artifacts.require('Prefunding.sol');
const MiniMeToken = artifacts.require('@aragon/apps-shared-minime/contracts/MiniMeToken')
const TokenManager = artifacts.require('TokenManager.sol');
const DAOFactory = artifacts.require('@aragon/core/contracts/factory/DAOFactory');
const EVMScriptRegistryFactory = artifacts.require('@aragon/core/contracts/factory/EVMScriptRegistryFactory');
const ACL = artifacts.require('@aragon/core/contracts/acl/ACL');
const Kernel = artifacts.require('@aragon/core/contracts/kernel/Kernel');
const ERC20 = artifacts.require('@aragon/core/contracts/lib/token/ERC20');
const getContract = name => artifacts.require(name);

const NOW = new Date().getTime() / 1000;
const HOURS = 3600;

const common = {

  Prefunding,

  ANY_ADDRESS: '0xffffffffffffffffffffffffffffffffffffffff',
  ZERO_ADDRESS: '0x0000000000000000000000000000000000000000',

  VESTING_CLIFF_DATE: NOW + 24 * HOURS,
  VESTING_COMPLETE_DATE: NOW + 72 * HOURS,
  FUNDING_GOAL: 20000,
  PERCENT_SUPPLY_OFFERED: 90,
  CONNECTOR_WEIGHT: 0.1,

  expectedExchangeRate: () => {
    return Math.floor(
      (common.FUNDING_GOAL / common.CONNECTOR_WEIGHT) / common.PERCENT_SUPPLY_OFFERED
    )
  },

  SALE_STATE: {
    PENDING: 0,
    FUNDING: 1,
    REFUNDING: 2,
    CLOSED: 3
  },

  deployDAOFactory: async (test) => {
    const kernelBase = await getContract('Kernel').new(true); // petrify immediately
    const aclBase = await getContract('ACL').new();
    const regFact = await EVMScriptRegistryFactory.new();
    test.daoFact = await DAOFactory.new(
      kernelBase.address,
      aclBase.address,
      regFact.address
    );
    test.APP_MANAGER_ROLE = await kernelBase.APP_MANAGER_ROLE();
  },

  deployDAO: async (test, daoManager) => {

    const daoReceipt = await test.daoFact.newDAO(daoManager);
    test.dao = Kernel.at(
      daoReceipt.logs.filter(l => l.event === 'DeployDAO')[0].args.dao
    );

    test.acl = ACL.at(await test.dao.acl());

    await test.acl.createPermission(
      daoManager,
      test.dao.address,
      test.APP_MANAGER_ROLE,
      daoManager,
      { from: daoManager }
    );
  },

  deployTokenManager: async (test, appManager) => {

    const appBase = await TokenManager.new();
    // test.CREATE_PROPOSALS_ROLE            = await appBase.CREATE_PROPOSALS_ROLE();

    const daoInstanceReceipt = await test.dao.newAppInstance(
      '0x123',
      appBase.address,
      '0x',
      false,
      { from: appManager }
    );

    const proxy = daoInstanceReceipt.logs.filter(l => l.event === 'NewAppProxy')[0].args.proxy;
    test.tokenManager = TokenManager.at(proxy);

    // await test.acl.createPermission(
    //   common.ANY_ADDRESS,
    //   test.app.address,
    //   test.CREATE_PROPOSALS_ROLE,
    //   appManager,
    //   { from: appManager }
    // );
  },

  deployApp: async (test, appManager) => {

    const appBase = await Prefunding.new();
    test.START_ROLE = await appBase.START_ROLE();
    test.BUY_ROLE = await appBase.BUY_ROLE();

    const daoInstanceReceipt = await test.dao.newAppInstance(
      '0x1234',
      appBase.address,
      '0x',
      false,
      { from: appManager }
    );

    const proxy = daoInstanceReceipt.logs.filter(l => l.event === 'NewAppProxy')[0].args.proxy;
    test.app = Prefunding.at(proxy);

    await test.acl.createPermission(
      appManager,
      test.app.address,
      test.START_ROLE,
      appManager,
      { from: appManager }
    );
    await test.acl.createPermission(
      common.ANY_ADDRESS,
      test.app.address,
      test.BUY_ROLE,
      appManager,
      { from: appManager }
    );
  },

  deployTokens: async (test) => {
    test.purchasingToken = await MiniMeToken.new(common.ZERO_ADDRESS, common.ZERO_ADDRESS, 0, 'DaiToken', 18, 'DAI', true);
    test.projectToken = await MiniMeToken.new(common.ZERO_ADDRESS, common.ZERO_ADDRESS, 0, 'ProjectToken', 18, 'PRO', true);
  },

  defaultSetup: async (test, managerAddress) => {

    // Deploy DAO.
    await common.deployDAOFactory(test);
    await common.deployDAO(test, managerAddress);

    // Deploy tokens and TokenManager.
    await common.deployTokens(test);
    await common.deployTokenManager(test, managerAddress);
    await test.projectToken.changeController(test.tokenManager.address);
    await test.tokenManager.initialize(
      test.projectToken.address,
      true, /* transferable */
      0 /* macAccountTokens (infinite if set to 0) */
    );

    // Deploy Prefunding app.
    await common.deployApp(test, managerAddress);
    await test.app.initialize(
      test.purchasingToken.address,
      test.projectToken.address,
      test.tokenManager.address,
      common.VESTING_CLIFF_DATE,
      common.VESTING_COMPLETE_DATE,
      common.FUNDING_GOAL,
      common.PERCENT_SUPPLY_OFFERED
    );
  },

  sendTransaction: (data) => {
    return new Promise((resolve, reject) => {
      web3.eth.sendTransaction(data, (err, txHash) => {
        if(err) reject(err);
        else resolve(txHash);
      });
    });
  }

};

module.exports = common;
