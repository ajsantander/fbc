const {
  DAI_FUNDING_GOAL,
  CONNECTOR_WEIGHT,
  PERCENT_SUPPLY_OFFERED,
  PPM
} = require('./constants')
const sha3 = require('js-sha3').keccak_256

const utils = {

  getEvent: (tx, eventName) => tx.logs.filter(log => log.event.includes(eventName))[0],

  assertExternalEvent: (tx, eventName, instances = 1) => {
    const events = tx.receipt.logs.filter(l => {
      return l.topics[0] === '0x' + sha3(eventName)
    })
    assert.equal(events.length, instances, `'${eventName}' event should have been fired ${instances} times`)
    return events
  },

  daiToProjectTokens: (dai) => {
    return dai * utils.daiToProjectTokenExchangeRate()
  },

  daiToProjectTokenExchangeRate: () => {
    const connectorWeightDec = CONNECTOR_WEIGHT / PPM;
    const supplyOfferedDec = PERCENT_SUPPLY_OFFERED / PPM;
    return Math.floor(
      (DAI_FUNDING_GOAL / connectorWeightDec) * supplyOfferedDec
    )
  },

  sendTransaction: (data) => {
    return new Promise((resolve, reject) => {
      web3.eth.sendTransaction(data, (err, txHash) => {
        if(err) reject(err)
        else resolve(txHash)
      })
    })
  }
}

module.exports = utils
