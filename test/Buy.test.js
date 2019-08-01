const {
  defaultSetup,
  sendTransaction,
  SALE_STATE,
  expectedExchangeRate
} = require('./common.js');
const { assertRevert } = require('@aragon/test-helpers/assertThrow');

const INIFINITE_ALLOWANCE = 100000000000000000;

const BUYER_1_PURCHASING_BALANCE = 100;

contract.only('Buy function', ([anyone, appManager, buyer1, buyer2]) => {

  before(() => defaultSetup(this, appManager));

  describe('When using other tokens', () => {

    it('Does not accept ETH', async () => {
      await assertRevert(
        sendTransaction({
          from: anyone,
          to: this.app.address,
          value: web3.toWei(1, 'ether')
        })
      );
    });

  });

  describe('When a user owns purchasing tokens', () => {

    before(async () => {
      await this.purchasingToken.generateTokens(buyer1, BUYER_1_PURCHASING_BALANCE);
    });

    it('User owns such tokens', async () => {
      const balance = await this.purchasingToken.balanceOf(buyer1);
      expect(balance.toNumber()).to.equal(BUYER_1_PURCHASING_BALANCE);
    });

    describe('When a user provides allowance for the purchasing token to the app', () => {

      before(async () => {
        await this.purchasingToken.approve(this.app.address, INIFINITE_ALLOWANCE, { from: buyer1 })
      });

      it('App should be allowed to transfer purchasing tokens', async () => {
        const allowance = await this.purchasingToken.allowance(buyer1, this.app.address);
        expect(allowance.toNumber()).to.equal(INIFINITE_ALLOWANCE);
      });

      it.skip('Reverts if the user attempts to buy tokens before the sale has started', async () => {
        // TODO
      });

      describe('When the sale has started', () => {

        before(async () => {
          await this.app.start({ from: appManager });
        });

        it('App state should be Funding', async () => {
          expect((await this.app.currentSaleState()).toNumber()).to.equal(SALE_STATE.FUNDING);
        });

        it('A user can ask the app how many project tokens would be obtained from a given amount of purchasing tokens', async () => {
          const amount = (await this.app.getProjectTokenAmount(BUYER_1_PURCHASING_BALANCE)).toNumber();
          const expectedAmount = BUYER_1_PURCHASING_BALANCE * expectedExchangeRate()
          expect(amount).to.equal(expectedAmount)
        });

        describe('When a user buys project tokens', () => {

          before(async () => {
            await this.app.buy(BUYER_1_PURCHASING_BALANCE, { from: buyer1 });
          });

          it('The purchasing tokens are transferred from the user to the app', async () => {
            const userBalance = (await this.purchasingToken.balanceOf(buyer1)).toNumber()
            const appBalance = (await this.purchasingToken.balanceOf(this.app.address)).toNumber()
            expect(userBalance).to.equal(0)
            expect(appBalance).to.equal(BUYER_1_PURCHASING_BALANCE)
          })

          it('Vested tokens are assigned to the buyer', async () => {
            const userBalance = (await this.projectToken.balanceOf(buyer1)).toNumber()
            const expectedAmount = BUYER_1_PURCHASING_BALANCE * expectedExchangeRate()
            expect(userBalance).to.equal(expectedAmount)
          });

          it.skip('The purchase produces a valid vesting id for the buyer', async () => {
            // TODO
          });

          it.skip('An event is emitted', async () => {
            // TODO
          });
        });
      });
    });
  });
});
