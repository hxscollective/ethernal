//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockedLINK {
  uint256 private balance;

  constructor(uint256 _balance) {
    balance = _balance;
  }

  function balanceOf(address) external view returns (uint256) {
    return balance;
  }

  function transferAndCall(
    address,
    uint256,
    bytes memory
  ) external payable returns (bool) {}
}
