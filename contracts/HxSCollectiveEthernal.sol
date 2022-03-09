// Work in Progress
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@chainlink/contracts/src/v0.8/VRFConsumerBase.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import 'hardhat/console.sol';

contract HxSCollectiveEthernal is ERC721Enumerable, Ownable, VRFConsumerBase {
  event RandomnessRequested(bytes32 requestId, uint256 tokenId);
  event RandomnessFulfilled(bytes32 requestId, uint256 tokenId, uint256 randomness);

  struct RandomnessOracle {
    // VRF Coodinator Address
    address coordinator;
    // LINK Contract Address
    address link;
    // Oracle Key Hash
    bytes32 keyHash;
    // Oracle Fee in LINK denoted in Jeuls
    uint256 fee;
    // Requests
    mapping(bytes32 => uint256) requests;
  }

  // Collection size, hard-set
  uint256 public collectionSize;

  // Token Data
  mapping(uint256 => uint256) public tokenData;

  // Token URIs
  mapping(uint256 => string) public tokenURIs;

  // Base Price, in ETH
  uint256 public price = 1 * (10 ^ 18);

  // Oracle
  RandomnessOracle public oracle;

  constructor(
    uint256 size,
    address coordinator,
    address link,
    bytes32 oracleKeyHash,
    uint256 fee
  ) ERC721('H x S Collective - Ethernal', 'HxSCollectiveEthernal') VRFConsumerBase(coordinator, link) {
    collectionSize = size;
    oracle.coordinator = coordinator;
    oracle.link = link;
    oracle.keyHash = oracleKeyHash;
    oracle.fee = fee;
  }

  /**
   * @dev See {IERC721Metadata-tokenURI}.
   */
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    require(_exists(tokenId), 'ERC721Metadata: URI query for nonexistent token');

    return tokenURIs[tokenId];
  }

  /**
   * @dev Mints the token with requirements described below and requests the randomness function.
   * Sender of the transaction is always considered as the buyer and after the entire flow, an event of RandomnessRequested is emited.
   */
  function mint() external payable {
    address buyer = msg.sender;

    // 1. Verify we can mint
    // 1.1 Verify the collection supply has not been exchausted already
    require(
      (totalSupply() + 1) <= collectionSize,
      errorMessage('Sorry, the maximum supply has been reached, the minting is finished')
    );

    // 1.2 Check if the buyer has not already bought maximum amount of allowed artwork
    require(balanceOf(buyer) < 5, errorMessage('You can own only 5 tokens per address'));

    // 2. Check if enough Ether has been sent
    require(msg.value >= price, errorMessage('Not enough Ether has been sent'));

    // 3. Check if we still have enough LINK to call the Oracle
    require(
      LINK.balanceOf(address(this)) > oracle.fee,
      errorMessage(
        'Not enough LINK in the contract to pay the Oracle - either fund it yourself and try again, or contact the creators'
      )
    );

    // 4. Mint the token
    uint256 tokenId = totalSupply() + 1;
    _safeMint(buyer, tokenId);

    // 4. Request the random number from the CHAINLINK Oracle
    bytes32 requestId = requestRandomness(oracle.keyHash, oracle.fee);

    // 4.1 Make sure requestId is never 0! Weird, but just in case
    require(requestId != 0, errorMessage('Request to get randomness cannot ever be 0'));

    // 4.2 Store the requestId mapped to tokenId
    oracle.requests[requestId] = tokenId;

    // 5. Emit the event
    emit RandomnessRequested(requestId, tokenId);
  }

  /**
   * @dev Allow only the owner to change the Oracle parameters
   * @param coordinator Address of the VRF Coordinator Contract
   * @param link Address of the LINK Contract
   * @param keyHash Key Hash for the VRF Coordinator
   * @param fee Fee for the Oracle in LINK denoted in Jeuls
   */
  function setOracle(
    address coordinator,
    address link,
    bytes32 keyHash,
    uint256 fee
  ) external onlyOwner {
    oracle.coordinator = coordinator;
    oracle.link = link;
    oracle.keyHash = keyHash;
    oracle.fee = fee;
  }

  /**
   * @dev Allow only the owner to set the token URI and once only afer the randomness has finished
   * @param tokenId ID of the token
   * @param uri URI pointing to the metadata of the token
   */
  function setTokenURI(uint256 tokenId, string memory uri) external onlyOwner {
    // 1. Make sure the URI is only set once
    require(bytes(tokenURIs[tokenId]).length == 0, errorMessage('Token URI can only be set once'));

    // 2. Make sure that the randomness has finished
    require(tokenData[tokenId] != 0, errorMessage('Randomness has not finished yet'));

    // 3. Set the token URI
    tokenURIs[tokenId] = uri;
  }

  /**
   * @dev Allows the owner and only the owner of the contact to withdraw all the balance
   */
  function withdraw() external payable onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  /**
   * @dev Fullfills randomness, setting the randomness value and assigning the random value to the collection data.
   * This function needs to always succeeed and never revert as the randomness value is unique and
   * the function is not called again.
   * @param requestId ID of the request for the random value
   * @param randomness Simple, the random number
   */
  function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
    uint256 tokenId = oracle.requests[requestId];

    // TODO: do something with the randomness maybe
    tokenData[tokenId] = randomness;

    emit RandomnessFulfilled(requestId, tokenId, randomness);
  }

  /**
   * @dev Returns error message formated with the contract name
   * @param message an error message to format
   * @return bytes message error messsage formatted with the contract name
   */
  function errorMessage(string memory message) internal view returns (string memory) {
    return string(abi.encodePacked(symbol(), ': ', message));
  }
}
