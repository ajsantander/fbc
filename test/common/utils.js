const {
  DAI_FUNDING_GOAL,
  CONNECTOR_WEIGHT,
  PERCENT_SUPPLY_OFFERED
} = require('./constants')
const sha3 = require('js-sha3').keccak_256

const utils = {

  assertExternalEvent: (tx, eventName, instances = 1) => {
    const events = tx.receipt.logs.filter(l => {
      return l.topics[0] === '0x' + sha3(eventName)
    })
    assert.equal(events.length, instances, `'${eventName}' event should have been fired ${instances} times`)
    return events
  },

  daiToProjectTokens: (dai) => {
    return dai * utils.daiToProjectTokenMultiplier()
  },

  daiToProjectTokenMultiplier: () => {
    return Math.floor(
      (DAI_FUNDING_GOAL / CONNECTOR_WEIGHT) / PERCENT_SUPPLY_OFFERED
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
