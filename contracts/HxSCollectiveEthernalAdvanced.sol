// Work in Progress
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@chainlink/contracts/src/v0.8/VRFConsumerBase.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

contract HxSCollectiveEthernalAdvanced is ERC721, Ownable, VRFConsumerBase {
  struct RandomnessOracle {
    // VRF Coodinator Address
    address coordinator;
    // LINK Contract Address
    address link;
    // Oracle Key Hash
    bytes32 keyHash;
    // Oracle Fee in LINK denoted in Jeuls
    uint256 fee;
    // Requests by Buyers
    mapping(address => bytes32) requests;
    // Responses for the Requests
    mapping(bytes32 => uint256) responses;
  }

  // Collection size, hard-set
  uint256 public collectionSize = 1000;

  // Collection Supply
  uint256 public collectionSupply;

  // Number of all minting requests
  uint256 public collectionRequests;

  // Collection Data
  mapping(uint256 => bytes) public collectionData;

  // Base Price, in ETH
  uint256 public price = 1 * (10 ^ 18);

  // Oracle
  RandomnessOracle private oracle;

  // Ether transfered by buyers
  mapping(address => uint256) private wallet;

  constructor(
    address oracleCoordinator,
    address oracleLink,
    bytes32 oracleKeyHash
  ) ERC721('H x S Collective - Ethernal', 'HxSCollectiveEthernal') VRFConsumerBase(oracleCoordinator, oracleLink) {
    oracle.coordinator = oracleCoordinator;
    oracle.link = oracleLink;
    oracle.keyHash = oracleKeyHash;
  }

  function totalSupply() external view returns (uint256) {
    return collectionSize;
  }

  function requestMinting() external payable {
    address buyer = msg.sender;

    // 1. Verify we can mint
    // 1.1 Verify the collection supply has not been exchausted already
    require(
      (collectionSupply + 1) <= collectionSize,
      errorMessage('Sorry, the maximum supply has been reached, the minting is finished')
    );

    // 1.2 Check if the buyer is not waiting for the randomness request and minting
    // Only one request for minting per address is allowed
    require(oracle.requests[buyer] == 0, errorMessage('You have already requested minting for this address'));

    // 1.4 Check if the buyer has not already bought maximum amount of allowed artwork
    require(balanceOf(buyer) == 0, errorMessage('You can own only one token per address during minting'));

    // 2. Check if enough ether for the price has been sent
    require(msg.value < price, errorMessage('Not enough ether has been sent'));

    // 3. Check if we still have enough LINK to call the Oracle
    require(
      LINK.balanceOf(address(this)) > oracle.fee,
      errorMessage(
        'Not enough LINK in the contract to pay the Oracle. Either fund it yourself and try again, or contact the creators'
      )
    );

    // 4. Store the ETH from buyer
    wallet[buyer] += msg.value;

    // 5. Request the random number from the CHAINLINK Oracle
    bytes32 requestId = requestRandomness(oracle.keyHash, oracle.fee);

    // 5.1 Make sure requestId is never 0! Weird, but just in case
    require(requestId != 0, errorMessage('Request to get randomness cannot ever be 0'));

    // 6. Store the request per buyer
    oracle.requests[buyer] = requestId;
    collectionRequests += 1;
  }

  function mint() external {
    address buyer = msg.sender;

    // 1. Make sure the buyer has requested the minting before and the request is completed
    require(canMint((buyer)), errorMessage('Minting is pending since the randomness request has not yet completed'));

    // 2. Make sure there's still enough balance from the buyer and they did not withdraw in the meantime
    require(wallet[buyer] >= price, errorMessage('Not enough ether to complete minting'));

    // 3. Minting
    bytes32 requestId = oracle.requests[buyer];
    uint256 randomness = oracle.responses[requestId];
    uint256 tokenId = collectionSupply += 1;

    // 3.1 Reset all request data for the buyer and claim the their wallet
    collectionRequests -= 1;
    oracle.requests[buyer] = 0;
    oracle.responses[requestId] = 0;
    wallet[buyer] -= price;

    // 3.2
    // TODO: Use randomness to define NFT data for the token, e.g.
    collectionData[tokenId] = bytes(Strings.toString(randomness));

    // 3.3 Mint and emit events
    _safeMint(buyer, tokenId);
  }

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
    @dev Allows the owner and only the owner of the contact to withdraw all the balance
  */
  function withdraw() external payable onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  /**
    @dev Allows the buyer to withdraw their request and balance
  */
  function withdawRequest() external payable {
    // 1. Check if the buyer has requested
  }

  function canMint(address buyer) public view returns (bool) {
    bytes32 requestId = oracle.requests[buyer];

    require(requestId != 0, 'No request for the buyer');

    uint256 randomness = oracle.responses[requestId];

    return randomness != 0;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    // TODO: implement

    return '';
  }

  /**
    @dev Fullfills randomness, only setting the value for request. Any other functionality should not be inside the function since the function should not ever revert
    @param requestId ID of the request for the random value
    @param randomness Simple, the random number
  */
  function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
    oracle.responses[requestId] = randomness;
  }

  /**
    @dev Returns error message formated with the contract name
    @param message an error message to format
    @return bytes message error messsage formatted with the contract name
  */
  function errorMessage(string memory message) internal view returns (string memory) {
    return string(abi.encodePacked(symbol(), ': ', message));
  }
}
