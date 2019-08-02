const FundraisingController = artifacts.require('FundraisingMock.sol');

const {
  defaultSetup,
  FUNDING_PERIOD,
  SALE_STATE,
  CONNECTOR_WEIGHT,
  TAP_RATE
} = require('./common.js')

const BUYERS_DAI_BALANCE = 20000
const INIFINITE_ALLOWANCE = 100000000000000000

contract('Close', ([anyone, appManager, buyer1]) => {

  describe('When purchases have been made and the sale is Closed', () => {

    before(async () => {
      await defaultSetup(this, appManager)
      await this.daiToken.generateTokens(buyer1, BUYERS_DAI_BALANCE)
      await this.daiToken.approve(this.app.address, INIFINITE_ALLOWANCE, { from: buyer1 })
      await this.app.start({ from: appManager })

      // Make a single purchase that reaches the funding goal
      await this.app.buy(BUYERS_DAI_BALANCE, {  from: buyer1 })

      await this.app.mockIncreaseTime(FUNDING_PERIOD)
      await this.app.close()
    })

    it('Sale state is Closed', async () => {
      expect((await this.app.currentSaleState()).toNumber()).to.equal(SALE_STATE.CLOSED);
    })

    it('Raised funds are transferred to the fundraising pool', async () => {
      const totalDaiRaised = (await this.app.totalDaiRaised()).toNumber()
      const fundraisingPool = await this.app.fundraisingPool()
      expect((await this.daiToken.balanceOf(this.app.address)).toNumber()).to.equal(0)
      expect((await this.daiToken.balanceOf(fundraisingPool)).toNumber()).to.equal(totalDaiRaised)
    })

    it('Fundraising app should be initialized correctly', async () => {
      expect(await this.fundraisingController.token()).to.equal(this.daiToken.address)
      expect((await this.fundraisingController.virtualSupply()).toNumber()).to.equal(0)
      expect((await this.fundraisingController.virtualBalance()).toNumber()).to.equal(0)
      expect((await this.fundraisingController.reserveRatio()).toNumber()).to.equal(1 / CONNECTOR_WEIGHT)
      expect((await this.fundraisingController.tap()).toNumber()).to.equal(TAP_RATE)
    })

  })
});
