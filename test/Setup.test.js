const {
  defaultSetup,
  FUNDING_GOAL,
  PERCENT_SUPPLY_OFFERED,
  VESTING_CLIFF_DATE,
  VESTING_COMPLETE_DATE,
  SALE_STATE
} = require('./common.js');
const { assertRevert } = require('@aragon/test-helpers/assertThrow');

contract.only('Setup', ([anyone, appManager]) => {

  describe('When deploying the app with valid parameters', () => {
    
    beforeEach(() => defaultSetup(this, appManager));

    it('App gets deployed', async () => {
      expect(web3.isAddress(this.app.address)).to.equal(true);
    });

    it('Funding goal and percentage offered are set', async () => {
      expect((await this.app.getFundingGoal()).toNumber()).to.equal(FUNDING_GOAL);
      expect((await this.app.getPercentSupplyOffered()).toNumber()).to.equal(PERCENT_SUPPLY_OFFERED);
    });

    it('Vesting dates are set', async () => {
      expect((await this.app.getVestingCliffDate()).toNumber()).to.be.closeTo(VESTING_CLIFF_DATE, 2);
      expect((await this.app.getVestingCompleteDate()).toNumber()).to.be.closeTo(VESTING_COMPLETE_DATE, 2);
    });

    it('Initial state is Pending', async () => {
      expect((await this.app.getCurrentSaleState()).toNumber()).to.equal(SALE_STATE.PENDING);
    });

    it('Project token is deployed and set in the app', async () => {
      expect(web3.isAddress(this.projectToken.address)).to.equal(true);
      expect((await this.app.getProjectToken())).to.equal(this.projectToken.address);
    });

    it('Purchasing token is deployed and set in the app', async () => {
      expect(web3.isAddress(this.purchasingToken.address)).to.equal(true);
      expect((await this.app.getPurchasingToken())).to.equal(this.purchasingToken.address);
    });

    it('TokenManager is deployed, set in the app, and controls the project token', async () => {
      expect(web3.isAddress(this.tokenManager.address)).to.equal(true);
      expect((await this.app.getPurchasingTokenManager())).to.equal(this.tokenManager.address);
    });

    it.skip('Exchange rate is calculated to the expected value', async () => {
      
    });

  });

});
