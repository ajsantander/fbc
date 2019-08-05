const {
  FUNDING_PERIOD,
  SALE_STATE,
  CONNECTOR_WEIGHT,
  TAP_RATE
} = require('./common/constants')
const { deployDefaultSetup } = require('./common/deploy')
const { assertExternalEvent } = require('./common/utils')
const FundraisingController = artifacts.require('FundraisingMock.sol')

const BUYERS_DAI_BALANCE = 20000

contract('Close', ([anyone, appManager, buyer1]) => {

  describe('When purchases have been made and the sale is Closed', () => {

    let closeReceipt

    before(async () => {
      await deployDefaultSetup(this, appManager)
      await this.daiToken.generateTokens(buyer1, BUYERS_DAI_BALANCE)
      await this.daiToken.approve(this.presale.address, BUYERS_DAI_BALANCE, { from: buyer1 })
      await this.presale.start({ from: appManager })

      // Make a single purchase that reaches the funding goal
      await this.presale.buy(BUYERS_DAI_BALANCE, {  from: buyer1 })

      await this.presale.mockIncreaseTime(FUNDING_PERIOD)
      closeReceipt = await this.presale.close()
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

    // TODO: Do not use assertExternalEvent (delete it) and use my own tool that I can use to verify the actual values
    it.skip('Fundraising app should be initialized correctly', async () => {
      assertExternalEvent(closeReceipt, 'AddTokenTap(address,uint256)') // tap
      assertExternalEvent(closeReceipt, 'AddCollateralToken(address)') // pool
      assertExternalEvent(closeReceipt, 'AddCollateralToken(address,uint256,uint256,uint32)') // market maker
    })

  })
})
