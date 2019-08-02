const {
  DAI_FUNDING_GOAL,
  CONNECTOR_WEIGHT,
  PERCENT_SUPPLY_OFFERED
} = require('./constants')

const utils = {

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
