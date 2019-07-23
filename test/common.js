const Prefunding = artifacts.require('Prefunding.sol');
const DAOFactory = artifacts.require('@aragon/core/contracts/factory/DAOFactory');
const EVMScriptRegistryFactory = artifacts.require('@aragon/core/contracts/factory/EVMScriptRegistryFactory');
const ACL = artifacts.require('@aragon/core/contracts/acl/ACL');
const Kernel = artifacts.require('@aragon/core/contracts/kernel/Kernel');
const getContract = name => artifacts.require(name);

const common = {

  Prefunding,

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

  deployApp: async (test, appManager) => {

    const appBase = await Prefunding.new();
    // test.CREATE_PROPOSALS_ROLE            = await appBase.CREATE_PROPOSALS_ROLE();

    const daoInstanceReceipt = await test.dao.newAppInstance(
      '0x1234',
      appBase.address,
      '0x',
      false,
      { from: appManager }
    );

    const proxy = daoInstanceReceipt.logs.filter(l => l.event === 'NewAppProxy')[0].args.proxy;
    test.app = Prefunding.at(proxy);

    // await test.acl.createPermission(
    //   common.ANY_ADDRESS,
    //   test.app.address,
    //   test.CREATE_PROPOSALS_ROLE,
    //   appManager,
    //   { from: appManager }
    // );
  },

  deployTokens: async (test) => {
    // test.voteToken = await MiniMeToken.new(common.ZERO_ADDRESS, common.ZERO_ADDRESS, 0, 'VoteToken', 18, 'ANT', true);
    // test.stakeToken = await MiniMeToken.new(common.ZERO_ADDRESS, common.ZERO_ADDRESS, 0, 'StakeToken', 18, 'GEN', true);
  },

  defaultSetup: async (test, managerAddress) => {
    await common.deployDAOFactory(test);
    await common.deployDAO(test, managerAddress);
    await common.deployApp(test, managerAddress);
    // await common.deployTokens(test);
    await test.app.initialize();
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
