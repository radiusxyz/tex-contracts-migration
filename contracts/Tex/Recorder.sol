//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.6;

import "hardhat/console.sol";

contract Recorder {
  uint256 public currentRound;
  uint256 public currentIndex;

  address public owner;

  constructor() public {
    currentRound = 0;
    currentIndex = 0;
    owner = msg.sender;
  }

  mapping(uint256 => bool) public isSaved;
  mapping(uint256 => bytes32[]) public roundTxIdList;
  mapping(bytes32 => mapping(address => bool)) public useOfVeto;

  function addTxIds(bytes32[] memory _txList) public {
    roundTxIdList[currentRound] = _txList;
    isSaved[currentRound] = true;
    currentIndex = 0;
  }

  function cancelTxId(bytes32 _txId) public {
    useOfVeto[_txId][msg.sender] = true;
  }

  function getRoundTxLnegth() public view returns (uint256) {
    return roundTxIdList[currentRound].length;
  }

  function isCancelTx(bytes32 _txId, address _txOwner) public view returns (bool)  {
    return useOfVeto[_txId][_txOwner] == true;
  }

  function validate(bytes32 _txId) public view returns (bool) {
    return roundTxIdList[currentRound][currentIndex] == _txId;
  }

  function goForward() public {
    currentIndex++;
    if (roundTxIdList[currentRound].length == currentIndex) {
      currentRound++;
      currentIndex = 0;
    }
  }
}
