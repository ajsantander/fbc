const {
  FUNDING_PERIOD,
  SALE_STATE
} = require('./common/constants')
const { daiToProjectTokens } = require('./common/utils')
const { deployDefaultSetup } = require('./common/deploy')

const BUYERS_DAI_BALANCE = 1000

contract('Refund', ([anyone, appManager, buyer1, buyer2, buyer3]) => {

  describe('When purchases have been made and the sale is Refunding', () => {

    before(async () => {
      await deployDefaultSetup(this, appManager)

      await this.daiToken.generateTokens(buyer1, BUYERS_DAI_BALANCE)
      await this.daiToken.generateTokens(buyer2, BUYERS_DAI_BALANCE)
      await this.daiToken.generateTokens(buyer3, BUYERS_DAI_BALANCE)

      await this.daiToken.approve(this.app.address, BUYERS_DAI_BALANCE, { from: buyer1 })
      await this.daiToken.approve(this.app.address, BUYERS_DAI_BALANCE, { from: buyer2 })
      await this.daiToken.approve(this.app.address, BUYERS_DAI_BALANCE, { from: buyer3 })

      await this.app.start({ from: appManager })

      // Make a few purchases, careful not to reach the funding goal.
      await this.app.buy(BUYERS_DAI_BALANCE, {  from: buyer1 }) // Spends everything in one purchase
      await this.app.buy(BUYERS_DAI_BALANCE / 2, {  from: buyer2 })
      await this.app.buy(BUYERS_DAI_BALANCE / 2, {  from: buyer2 }) // Spends everything in two purchases
      await this.app.buy(BUYERS_DAI_BALANCE / 2, {  from: buyer3 }) // Spends half

      await this.app.mockIncreaseTime(FUNDING_PERIOD)
    })

    // TODO: Test invalid attempts to get refunded before the sale closes

    it('Sale state is Refunding', async () => {
      expect((await this.app.currentSaleState()).toNumber()).to.equal(SALE_STATE.REFUNDING)
    })

    it('Provided buyers with project tokens, at the expense of dai', async () => {
      expect((await this.daiToken.balanceOf(buyer1)).toNumber()).to.equal(0)
      expect((await this.daiToken.balanceOf(buyer2)).toNumber()).to.equal(0)
      expect((await this.daiToken.balanceOf(buyer3)).toNumber()).to.equal(BUYERS_DAI_BALANCE / 2)
      expect((await this.projectToken.balanceOf(buyer1)).toNumber()).to.equal(daiToProjectTokens(BUYERS_DAI_BALANCE))
      expect((await this.projectToken.balanceOf(buyer2)).toNumber()).to.equal(daiToProjectTokens(BUYERS_DAI_BALANCE))
      expect((await this.projectToken.balanceOf(buyer3)).toNumber()).to.equal(daiToProjectTokens(BUYERS_DAI_BALANCE / 2))
    })

    it('Allows a buyer who made a single purchase to get refunded', async () => {
      await this.app.refund(buyer1, 0)
      expect((await this.daiToken.balanceOf(buyer1)).toNumber()).to.equal(BUYERS_DAI_BALANCE)
      expect((await this.projectToken.balanceOf(buyer1)).toNumber()).to.equal(0)
    })

    it.skip('Allows a buyer who made multiple purchases to get refunded', async () => {
      // TODO
    })

    it.skip('Should deny a buyer to get a refund for a purchase that wasn\'t made', async () => {
      // TODO
    })
  })
})
