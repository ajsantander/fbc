const {
  SALE_STATE
} = require('./common/constants')
const { sendTransaction, daiToProjectTokens } = require('./common/utils')
const { deployDefaultSetup } = require('./common/deploy')
const { assertRevert } = require('@aragon/test-helpers/assertThrow')

const BUYER_DAI_BALANCE = 100
const INIFINITE_ALLOWANCE = 100000000000000000

contract('Buy', ([anyone, appManager, buyer]) => {

  before(() => deployDefaultSetup(this, appManager))

  describe('When using other tokens', () => {

    it('Does not accept ETH', async () => {
      await assertRevert(
        sendTransaction({
          from: anyone,
          to: this.app.address,
          value: web3.toWei(1, 'ether')
        })
      )
    })

  })

  describe('When using dai', () => {

    before(async () => {
      await this.daiToken.generateTokens(buyer, BUYER_DAI_BALANCE)
      await this.daiToken.approve(this.app.address, INIFINITE_ALLOWANCE, { from: buyer })
    })

    it.skip('Reverts if the user attempts to buy tokens before the sale has started', async () => {
      // TODO
    })

    describe('When the sale has started', () => {

      before(async () => {
        await this.app.start({ from: appManager })
      })

      it('App state should be Funding', async () => {
        expect((await this.app.currentSaleState()).toNumber()).to.equal(SALE_STATE.FUNDING)
      })

      it('A user can ask the app how many project tokens would be obtained from a given amount of dai', async () => {
        const amount = (await this.app.daiToProjectTokens(BUYER_DAI_BALANCE)).toNumber()
        const expectedAmount = daiToProjectTokens(BUYER_DAI_BALANCE)
        expect(amount).to.equal(expectedAmount)
      })

      describe('When a user buys project tokens', () => {

        before(async () => {
          await this.app.buy(BUYER_DAI_BALANCE, { from: buyer })
        })

        it('The dai are transferred from the user to the app', async () => {
          const userBalance = (await this.daiToken.balanceOf(buyer)).toNumber()
          const appBalance = (await this.daiToken.balanceOf(this.app.address)).toNumber()
          expect(userBalance).to.equal(0)
          expect(appBalance).to.equal(BUYER_DAI_BALANCE)
        })

        it('Vested tokens are assigned to the buyer', async () => {
          const userBalance = (await this.projectToken.balanceOf(buyer)).toNumber()
          const expectedAmount = daiToProjectTokens(BUYER_DAI_BALANCE)
          expect(userBalance).to.equal(expectedAmount)
        })

        it.skip('The purchase produces a valid purchase id for the buyer', async () => {
          // TODO
        })

        it.skip('An event is emitted', async () => {
          // TODO
        })
      })
    })
  })
})
