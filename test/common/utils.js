const {
  DAI_FUNDING_GOAL,
  CONNECTOR_WEIGHT,
  PERCENT_SUPPLY_OFFERED
} = require('./constants')
const sha3 = require('js-sha3').keccak_256

const utils = {

  getEvent: (tx, eventName) => tx.logs.filter(log => log.event.includes(eventName))[0],

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
