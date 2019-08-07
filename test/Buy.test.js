const {
  SALE_STATE,
  FUNDING_PERIOD,
  DAI_FUNDING_GOAL
} = require('./common/constants')
const {
  sendTransaction,
  daiToProjectTokens,
  getEvent,
} = require('./common/utils')
const { deployDefaultSetup } = require('./common/deploy')
const { assertRevert } = require('@aragon/test-helpers/assertThrow')

const BUYER_1_DAI_BALANCE = 100
const BUYER_2_DAI_BALANCE = 100000

contract('Buy', ([anyone, appManager, buyer1, buyer2]) => {

  before(() => deployDefaultSetup(this, appManager))

  describe('When using other tokens', () => {

    it('Does not accept ETH', async () => {
      await assertRevert(
        sendTransaction({ from: anyone, to: this.presale.address, value: web3.toWei(1, 'ether') })
      )
    })

  })

  describe('When using dai', () => {

    before(async () => {
      await this.daiToken.generateTokens(buyer1, BUYER_1_DAI_BALANCE)
      await this.daiToken.generateTokens(buyer2, BUYER_2_DAI_BALANCE)
      await this.daiToken.approve(this.presale.address, BUYER_1_DAI_BALANCE, { from: buyer1 })
      await this.daiToken.approve(this.presale.address, BUYER_2_DAI_BALANCE, { from: buyer2 })
    })

    it('Reverts if the user attempts to buy tokens before the sale has started', async () => {
      await assertRevert(
        this.presale.buy(BUYER_1_DAI_BALANCE, { from: buyer1 }),
        'PRESALE_INVALID_STATE'
      )
    })

    describe('When the sale has started', () => {

      let startTime

      before(async () => {
        startTime = new Date().getTime() / 1000
        await this.presale.start({ from: appManager })
      })

      it('App state should be Funding', async () => {
        expect((await this.presale.currentSaleState()).toNumber()).to.equal(SALE_STATE.FUNDING)
      })

      it('A user can query how many tokens would be obtained for a given amount of dai', async () => {
        const amount = (await this.presale.daiToProjectTokens(BUYER_1_DAI_BALANCE)).toNumber()
        const expectedAmount = daiToProjectTokens(BUYER_1_DAI_BALANCE)
        expect(amount).to.equal(expectedAmount)
      })

      describe('When a user buys project tokens', () => {

        let purchaseTx;
        let initialProjectTokenSupply

        before(async () => {
          initialProjectTokenSupply = (await this.projectToken.totalSupply()).toNumber()
          purchaseTx = await this.presale.buy(BUYER_1_DAI_BALANCE, { from: buyer1 })
        })

        it('Project tokens are minted on purchases', async () => {
          const expectedAmount = daiToProjectTokens(BUYER_1_DAI_BALANCE)
          expect((await this.projectToken.totalSupply()).toNumber()).to.equal(initialProjectTokenSupply + expectedAmount)
        })

        it('The dai are transferred from the buyer to the app', async () => {
          const userBalance = (await this.daiToken.balanceOf(buyer1)).toNumber()
          const appBalance = (await this.daiToken.balanceOf(this.presale.address)).toNumber()
          expect(userBalance).to.equal(0)
          expect(appBalance).to.equal(BUYER_1_DAI_BALANCE)
        })

        it('Vested tokens are assigned to the buyer', async () => {
          const userBalance = (await this.projectToken.balanceOf(buyer1)).toNumber()
          const expectedAmount = daiToProjectTokens(BUYER_1_DAI_BALANCE)
          expect(userBalance).to.equal(expectedAmount)
        })

        it('A TokensPurchased event is emitted', async () => {
          const expectedAmount = daiToProjectTokens(BUYER_1_DAI_BALANCE)
          const event = getEvent(purchaseTx, 'TokensPurchased')
          expect(event).to.exist
          expect(event.args.buyer).to.equal(buyer1)
          expect(event.args.daiSpent.toNumber()).to.equal(BUYER_1_DAI_BALANCE)
          expect(event.args.tokensPurchased.toNumber()).to.equal(expectedAmount)
          expect(event.args.purchaseId.toNumber()).to.equal(0)
        })

        it('The purchase produces a valid purchase id for the buyer', async () => {
          await this.presale.buy(1, { from: buyer2 })
          await this.presale.buy(2, { from: buyer2 })
          const tx = await this.presale.buy(3, { from: buyer2 })
          const event = getEvent(tx, 'TokensPurchased')
          expect(event.args.purchaseId.toNumber()).to.equal(2)
        })

        it('Keeps track of total dai raised', async () => {
          const raised = await this.presale.totalDaiRaised()
          expect(raised.toNumber()).to.equal(BUYER_1_DAI_BALANCE + 6)
        })

        it('Keeps track of independent purchases', async () => {
          expect((await this.presale.purchases(buyer1, 0)).toNumber()).to.equal(BUYER_1_DAI_BALANCE)
          expect((await this.presale.purchases(buyer2, 0)).toNumber()).to.equal(1)
          expect((await this.presale.purchases(buyer2, 1)).toNumber()).to.equal(2)
          expect((await this.presale.purchases(buyer2, 2)).toNumber()).to.equal(3)
        })

        it('A purchase cannot cause totalDaiRaised to be greater than the fundingGoal', async () => {
          await assertRevert(
            this.presale.buy(DAI_FUNDING_GOAL * 2, { from: buyer2 }),
            'PRESALE_EXCEEDS_FUNDING_GOAL'
          )
        })

        describe('When the sale is Refunding', () => {

          before(async () => {
            await this.presale.mockSetTimestamp(startTime + FUNDING_PERIOD)
          })

          it('Sale state is Refunding', async () => {
            expect((await this.presale.currentSaleState()).toNumber()).to.equal(SALE_STATE.REFUNDING)
          })

          it('Reverts if a user attempts to buy tokens', async () => {
            await assertRevert(
              this.presale.buy(1, { from: buyer2 }),
              'PRESALE_INVALID_STATE'
            )
          })
        })

        describe('When the sale state is GoalReached', () => {

          before(async () => {
            await this.presale.mockSetTimestamp(startTime + 1)

            const totalDaiRaised = (await this.presale.totalDaiRaised()).toNumber()
            await this.presale.buy(DAI_FUNDING_GOAL - totalDaiRaised, { from: buyer2 })
          })

          it('Sale state is GoalReached', async () => {
            expect((await this.presale.currentSaleState()).toNumber()).to.equal(SALE_STATE.GOAL_REACHED)
          })

          it('Reverts if a user attempts to buy tokens', async () => {
            await assertRevert(
              this.presale.buy(1, { from: buyer2 }),
              'PRESALE_INVALID_STATE'
            )
          })
        })
      })
    })
  })
})
