pragma solidity >=0.5.0;

library Swap {
  struct EIP712Swap {
    address txOwner;
    bytes4 functionSelector;
    uint256 amountIn;
    uint256 amountOut;
    address[] path;
    address to;
    uint256 nonce;
    uint256 deadline;
  }

  struct TxOrderMsg {
    uint256 round;
    uint256 order;
    bytes32 txId;
    bytes32 proof;
    bytes32 r;
    bytes32 s;
    uint8 v;
  }

  struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
  }

  
}
