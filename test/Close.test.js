const {
  FUNDING_PERIOD,
  SALE_STATE,
  CONNECTOR_WEIGHT,
  TAP_RATE
} = require('./common/constants')
const { deployDefaultSetup } = require('./common/deploy')
const FundraisingController = artifacts.require('FundraisingMock.sol')

const BUYERS_DAI_BALANCE = 20000

contract('Close', ([anyone, appManager, buyer1]) => {

  describe('When purchases have been made and the sale is Closed', () => {

    before(async () => {
      await deployDefaultSetup(this, appManager)
      await this.daiToken.generateTokens(buyer1, BUYERS_DAI_BALANCE)
      await this.daiToken.approve(this.presale.address, BUYERS_DAI_BALANCE, { from: buyer1 })
      await this.presale.start({ from: appManager })

      // Make a single purchase that reaches the funding goal
      await this.presale.buy(BUYERS_DAI_BALANCE, {  from: buyer1 })

      await this.presale.mockIncreaseTime(FUNDING_PERIOD)
      await this.presale.close()
    })

    it('Sale state is Closed', async () => {
      expect((await this.presale.currentSaleState()).toNumber()).to.equal(SALE_STATE.CLOSED)
    })

    it('Raised funds are transferred to the fundraising pool', async () => {
      const totalDaiRaised = (await this.presale.totalDaiRaised()).toNumber()
      const fundraisingPool = await this.presale.fundraisingPool()
      expect((await this.daiToken.balanceOf(this.presale.address)).toNumber()).to.equal(0)
      expect((await this.daiToken.balanceOf(fundraisingPool)).toNumber()).to.equal(totalDaiRaised)
    })

    it('Fundraising app should be initialized correctly', async () => {
      expect(await this.fundraising.token()).to.equal(this.daiToken.address)
      expect((await this.fundraising.virtualSupply()).toNumber()).to.equal(0)
      expect((await this.fundraising.virtualBalance()).toNumber()).to.equal(0)
      expect((await this.fundraising.reserveRatio()).toNumber()).to.equal(1 / CONNECTOR_WEIGHT)
      expect((await this.fundraising.tap()).toNumber()).to.equal(TAP_RATE)
    })

  })
})
