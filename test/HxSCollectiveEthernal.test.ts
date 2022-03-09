/* eslint-disable camelcase */
/* eslint-disable no-unused-expressions */
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { HxSCollectiveEthernal, HxSCollectiveEthernal__factory, MockedLINK__factory, MockedLINK } from '../typechain'

const [KEY_HASH, FEE] = [process.env.TESTING_CHAINLINK_KEY_HASH!, Number(process.env.TESTING_CHAINLINK_FEE!)]

describe('HxSCollectiveEthernal', () => {
  let owner: SignerWithAddress

  // Link Contract
  let LINK: MockedLINK__factory
  let link: MockedLINK
  const defaultLinkBalance = FEE + 1
  let linkBalance = defaultLinkBalance

  // NFT Contract
  let Contract: HxSCollectiveEthernal__factory
  let instance: HxSCollectiveEthernal
  const collectionSize = 10

  // Events
  let randomnessRequestedEvent: Promise<{ requestId: string; tokenId: number }>
  let randomnessFulfilledEvent: Promise<{ requestId: string; tokenId: number; randomness: number }>

  beforeEach(async () => {
    ;[owner] = await ethers.getSigners()

    // Mocked LINK contract to get the balanceOf
    LINK = await ethers.getContractFactory('MockedLINK')
    link = await LINK.connect(owner).deploy(linkBalance)

    // NFT Contract
    Contract = await ethers.getContractFactory('HxSCollectiveEthernal')

    // Non-existing addresses for CHAINLINK for the purpose of testing, doesn't matter since they are mocked anyway
    // Owner acts as a coordinator, so we can call rawFulfillRandomness
    instance = await Contract.connect(owner).deploy(collectionSize, owner.address, link.address, KEY_HASH, FEE)

    // Events
    randomnessRequestedEvent = new Promise((resolve, reject) => {
      instance.on('RandomnessRequested', async (requestId, tokenId) => {
        resolve({ requestId: requestId.toString(), tokenId: tokenId.toNumber() })
      })

      setTimeout(() => {
        reject(new Error('Timeout: RandomnessRequested event'))
      }, 60000)
    })

    randomnessFulfilledEvent = new Promise((resolve, reject) => {
      instance.on('RandomnessFulfilled', async (requestId, tokenId, randomness) => {
        resolve({ requestId: requestId.toString(), tokenId: tokenId.toNumber(), randomness: randomness.toNumber() })
      })

      setTimeout(() => {
        reject(new Error('Timeout: RandomnessFulfilled event'))
      }, 60000)
    })
  })

  it('deploys the contract', async () => {
    expect(instance.deployTransaction.hash).to.not.be.undefined
    expect(instance.deployTransaction.from).to.eql(owner.address)
  })

  it('correctly sets the Oracle attributes', async () => {
    const oracle = await instance.oracle()

    expect(oracle.coordinator).to.eql(owner.address)
    expect(oracle.link).to.eql(link.address)
    expect(oracle.keyHash).to.eql(KEY_HASH)
    expect(oracle.fee.toNumber()).to.eql(Number(FEE))

    expect(oracle.coordinator).not.to.be.undefined
    expect(oracle.link).not.to.be.undefined
    expect(oracle.keyHash).not.to.be.undefined
    expect(oracle.fee).not.to.be.undefined
  })

  describe('#totalSupply', async () => {
    it('returns the total supply of the collection', async () => {
      expect(await instance.totalSupply()).to.equal(0)

      const buyer = (await ethers.getSigners())[1]

      await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })

      expect(await instance.totalSupply()).to.equal(1)
    })
  })

  describe('#mint', async () => {
    it('mints the token for the buyer', async () => {
      const buyer = (await ethers.getSigners())[1]

      await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })

      expect((await instance.balanceOf(buyer.address)).toNumber()).to.eql(1)
      expect((await instance.tokenOfOwnerByIndex(buyer.address, 0)).toNumber()).to.eql(1)
    })

    describe('when the maximum supply is reached', async () => {
      it('reverts with an error', async () => {
        for (let i = 0; i < collectionSize; i++) {
          const buyer = (await ethers.getSigners())[i]

          await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })
        }

        const buyer = (await ethers.getSigners())[collectionSize]

        await expect(instance.connect(buyer).mint({ from: buyer.address, value: instance.price() })).to.be.revertedWith(
          'HxSCollectiveEthernal: Sorry, the maximum supply has been reached, the minting is finished',
        )
      })
    })

    describe('when the buyer already owns maximum allowed amount of tokens', async () => {
      it('reverts with an error', async () => {
        const buyer = (await ethers.getSigners())[1]

        for (let i = 0; i < 5; i++) {
          await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })
        }

        expect((await instance.balanceOf(buyer.address)).toNumber()).to.eql(5)

        await expect(
          instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() }),
        ).to.be.revertedWith('HxSCollectiveEthernal: You can own only 5 tokens per address')

        expect((await instance.balanceOf(buyer.address)).toNumber()).to.eql(5)
      })
    })

    describe('when the buyer did not send enough Ether', async () => {
      it('reverts with an error', async () => {
        const buyer = (await ethers.getSigners())[1]

        await expect(instance.connect(buyer).mint({ from: buyer.address, value: 0 })).to.be.revertedWith(
          'HxSCollectiveEthernal: Not enough Ether has been sent',
        )
      })
    })

    describe('when the contract does not have enough LINK to pay the Oracle', async () => {
      before(async () => {
        linkBalance = 0
      })

      after(async () => {
        linkBalance = defaultLinkBalance
      })

      it('reverts with an error', async () => {
        const buyer = (await ethers.getSigners())[1]

        await expect(
          instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() }),
        ).to.be.revertedWith(
          'HxSCollectiveEthernal: Not enough LINK in the contract to pay the Oracle - either fund it yourself and try again, or contact the creators',
        )
      })
    })
  })

  describe('#tokenURI', async () => {
    describe('when the tokens does not exist', async () => {
      it('returns an error', async () => {
        await expect(instance.tokenURI(1230000000)).to.be.revertedWith(
          'ERC721Metadata: URI query for nonexistent token',
        )
      })
    })
  })

  describe('#fulfillRandomness', async () => {
    it('fulfills the randomness and emits an event', async () => {
      const buyer = (await ethers.getSigners())[1]

      await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })

      const { requestId, tokenId } = (await randomnessRequestedEvent) as any

      expect(requestId).not.to.be.undefined
      expect(tokenId).not.to.be.undefined

      await instance.connect(owner).rawFulfillRandomness(requestId, tokenId, { from: owner.address })

      const {
        requestId: fulfilledRequestId,
        tokenId: fulfilledTokenId,
        randomness,
      } = (await randomnessFulfilledEvent) as any

      expect(fulfilledRequestId).to.eql(requestId)
      expect(fulfilledTokenId).to.eql(fulfilledTokenId)
      expect(randomness).to.not.be.undefined

      const data = await instance.tokenData(tokenId)

      expect(data.toNumber()).to.eql(randomness)
    })
  })

  describe('#setTokenURI', async () => {
    it('allows only the owner to change the URI', async () => {
      const buyer = (await ethers.getSigners())[1]

      await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })

      const tokenId = (await instance.tokenOfOwnerByIndex(buyer.address, 0)).toNumber()

      const { requestId } = await randomnessRequestedEvent
      await instance.connect(owner).rawFulfillRandomness(requestId, tokenId, { from: owner.address })
      await randomnessFulfilledEvent

      await expect(instance.connect(buyer).setTokenURI(tokenId, '123', { from: buyer.address })).to.be.revertedWith(
        'Ownable: caller is not the owner',
      )

      await instance.connect(owner).setTokenURI(tokenId, 'https://nft.xyz/123', { from: owner.address })

      expect(await instance.tokenURI(tokenId)).to.eql('https://nft.xyz/123')
    })

    describe('when the randomness has not finished yet', async () => {
      it('reverts with an error', async () => {
        const buyer = (await ethers.getSigners())[1]

        await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })

        const tokenId = (await instance.tokenOfOwnerByIndex(buyer.address, 0)).toNumber()

        await expect(
          instance.connect(owner).setTokenURI(tokenId, 'https://nft.xyz/123', { from: owner.address }),
        ).to.be.revertedWith('HxSCollectiveEthernal: Randomness has not finished yet')
      })
    })

    describe('when the URI has already been set', async () => {
      it('reverts since it allows only the owner to set the URI once', async () => {
        const buyer = (await ethers.getSigners())[1]

        await instance.connect(buyer).mint({ from: buyer.address, value: await instance.price() })

        const tokenId = (await instance.tokenOfOwnerByIndex(buyer.address, 0)).toNumber()

        const { requestId } = await randomnessRequestedEvent
        await instance.connect(owner).rawFulfillRandomness(requestId, tokenId, { from: owner.address })
        await randomnessFulfilledEvent

        await instance.connect(owner).setTokenURI(tokenId, 'https://nft.xyz/123', { from: owner.address })

        await expect(
          instance.connect(owner).setTokenURI(tokenId, 'https://nft.xyz/1234', { from: owner.address }),
        ).to.be.revertedWith('HxSCollectiveEthernal: Token URI can only be set once')
      })
    })
  })
})
