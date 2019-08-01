const {
  defaultSetup,
  FUNDING_PERIOD,
  SALE_STATE
} = require('./common.js')

const BUYERS_DAI_BALANCE = 10000
const INIFINITE_ALLOWANCE = 100000000000000000

contract.only('Refund', ([anyone, appManager, buyer1, buyer2, buyer3]) => {

  describe('When purchases have been made and the sale is Refunding', () => {

    before(async () => {
      await defaultSetup(this, appManager)

      await this.daiToken.generateTokens(buyer1, BUYERS_DAI_BALANCE)
      await this.daiToken.generateTokens(buyer2, BUYERS_DAI_BALANCE)
      await this.daiToken.generateTokens(buyer3, BUYERS_DAI_BALANCE)

      await this.daiToken.approve(this.app.address, INIFINITE_ALLOWANCE, { from: buyer1 })
      await this.daiToken.approve(this.app.address, INIFINITE_ALLOWANCE, { from: buyer2 })
      await this.daiToken.approve(this.app.address, INIFINITE_ALLOWANCE, { from: buyer3 })

      await this.app.start({ from: appManager })
      await this.app.mockIncreaseTime(FUNDING_PERIOD)
    })

    it('Sale state is Refunding', async () => {
      expect((await this.app.currentSaleState()).toNumber()).to.equal(SALE_STATE.REFUNDING);
    });

  })
});
