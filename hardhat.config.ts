import * as dotenv from 'dotenv'

import { extendEnvironment, HardhatUserConfig } from 'hardhat/config'
import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
import logger from './utils/logger'

dotenv.config()

const { ALCHEMY_KEY, TESTING_ACCOUNT_PRIVATE_KEY } = process.env

// Import tasks
require('./tasks')

// Config
const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.4',
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  defaultNetwork: 'hardhat',
  networks: {
    localhost: {
      url: 'http://127.0.0.1:8545',
      mining: {
        auto: false,
        interval: 5000,
      },
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${TESTING_ACCOUNT_PRIVATE_KEY}`],
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${TESTING_ACCOUNT_PRIVATE_KEY}`],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: 'USD',
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
}

extendEnvironment(hre => {
  logger.setSettings({ name: `${process.env.APP_NAME} network:${hre.network.name}` })
})

export default config
