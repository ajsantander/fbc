const {
  FUNDING_PERIOD,
  DAI_FUNDING_GOAL,
  SALE_STATE
} = require('./common/constants')
const { deployDefaultSetup } = require('./common/deploy')
const { assertExternalEvent } = require('./common/utils')

contract('Fundraising', ([anyone, appManager, buyer]) => {

  describe('When a sale closed', () => {

    let closeReceipt

    before(async () => {
      await deployDefaultSetup(this, appManager)

      const startDate = new Date().getTime() / 1000
      await this.presale.start({ from: appManager })

      await this.daiToken.generateTokens(buyer, DAI_FUNDING_GOAL)
      await this.daiToken.approve(this.presale.address, DAI_FUNDING_GOAL, { from: buyer })
      await this.presale.buy(DAI_FUNDING_GOAL, { from: buyer })

      await this.presale.mockSetTimestamp(startDate + FUNDING_PERIOD)

      closeReceipt = await this.presale.close()
    })

    it('The state is Closed', async () => {
      expect((await this.presale.currentSaleState()).toNumber()).to.equal(SALE_STATE.CLOSED)
    })

    it('Events related to adding a collateral token in the Fundraising app are triggered', async () => {
      assertExternalEvent(closeReceipt, 'AddTokenTap(address,uint256)') // Tap
      assertExternalEvent(closeReceipt, 'AddCollateralToken(address)') // Pool
      assertExternalEvent(closeReceipt, 'AddCollateralToken(address,uint256,uint256,uint32)') // Market maker
    })

    // TODO: Add more tests to verify the validity of the Fundraising app initialization.
  })
})
