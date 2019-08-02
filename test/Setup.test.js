const {
  defaultSetup,
  DAI_FUNDING_GOAL,
  PERCENT_SUPPLY_OFFERED,
  VESTING_CLIFF_DATE,
  VESTING_COMPLETE_DATE,
  SALE_STATE,
  CONNECTOR_WEIGHT,
  daiToProjectTokenMultiplier,
} = require('./common.js');
const { assertRevert } = require('@aragon/test-helpers/assertThrow');

contract('Setup', ([anyone, appManager]) => {

  describe('When deploying the app with valid parameters', () => {

    before(() => defaultSetup(this, appManager));

    it('App gets deployed', async () => {
      expect(web3.isAddress(this.app.address)).to.equal(true);
    });

    it('Funding goal and percentage offered are set', async () => {
      expect((await this.app.daiFundingGoal()).toNumber()).to.equal(DAI_FUNDING_GOAL);
      expect((await this.app.percentSupplyOffered()).toNumber()).to.equal(PERCENT_SUPPLY_OFFERED);
    });

    it('Vesting dates are set', async () => {
      expect((await this.app.vestingCliffDate()).toNumber()).to.be.closeTo(VESTING_CLIFF_DATE, 2);
      expect((await this.app.vestingCompleteDate()).toNumber()).to.be.closeTo(VESTING_COMPLETE_DATE, 2);
    });

    it('Initial state is Pending', async () => {
      expect((await this.app.currentSaleState()).toNumber()).to.equal(SALE_STATE.PENDING);
    });

    it('Project token is deployed and set in the app', async () => {
      expect(web3.isAddress(this.projectToken.address)).to.equal(true);
      expect((await this.app.projectToken())).to.equal(this.projectToken.address);
    });

    it('Dai token is deployed and set in the app', async () => {
      expect(web3.isAddress(this.daiToken.address)).to.equal(true);
      expect((await this.app.daiToken())).to.equal(this.daiToken.address);
    });

    it('TokenManager is deployed, set in the app, and controls the project token', async () => {
      expect(web3.isAddress(this.tokenManager.address)).to.equal(true);
      expect((await this.app.projectTokenManager())).to.equal(this.tokenManager.address);
    });

    it('Exchange rate is calculated to the expected value', async () => {
      const receivedValue = (await this.app.daiToProjectTokenMultiplier()).toNumber();
      expect(receivedValue).to.equal(daiToProjectTokenMultiplier());
    });

    it.skip('Fundraising controller and parameters are set up correctly', async () => {
      // TODO
    })
  });
});
