const {
  defaultSetup
} = require('./common.js');

contract('Prefunding', ([appManager]) => {

  describe('Base testing', () => {
    
    beforeEach(() => defaultSetup(this, appManager));

    it('App gets deployed', async () => {
      expect(web3.isAddress(this.app.address)).to.equal(true);
    });

    // it('Does not accept ETH', async () => {
      
    // });
  });
});
