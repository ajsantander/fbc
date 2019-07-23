const {
  defaultSetup,
  sendTransaction
} = require('./common.js');
const { assertRevert } = require('@aragon/test-helpers/assertThrow');

contract('Prefunding', ([anyone, appManager]) => {

  describe('Base testing', () => {
    
    beforeEach(() => defaultSetup(this, appManager));

    it('App gets deployed', async () => {
      expect(web3.isAddress(this.app.address)).to.equal(true);
    });

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
});
