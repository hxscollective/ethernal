import { task } from 'hardhat/config'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-ethers'
import logger from '../utils/logger'

task('get-balance', "Prints an account's balance")
  .addOptionalParam(
    'address',
    "The account's address - if not provided, prints the first account from config for the network",
  )
  .setAction(async (args, hre) => {
    const { ethers, waffle } = hre
    const [account] = await ethers.getSigners()
    const provider = waffle.provider
    const balance = await provider.getBalance(args.account || account.address)

    logger.info(`Balance for [${account.address}] is [${balance}] gwei / [${ethers.utils.formatEther(balance)}] ETH`, {
      account: account.address,
      balance,
    })
  })
