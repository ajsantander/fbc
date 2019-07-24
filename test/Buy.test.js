const {
  defaultSetup,
  sendTransaction
} = require('./common.js');
const { assertRevert } = require('@aragon/test-helpers/assertThrow');

contract('Buy function', ([anyone, appManager]) => {

  beforeEach(() => defaultSetup(this, appManager));

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

});
