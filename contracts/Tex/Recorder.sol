pragma experimental ABIEncoderV2;
pragma solidity ^0.6.6;

import "hardhat/console.sol";

import "./libraries/Swap.sol";

import "./interfaces/IRecorder.sol";

contract Recorder is IRecorder {
  address private owner;
  address public operator;

  uint256 public currentRound;
  uint256 public currentIndex;

  bytes32 public router_domain_seperator;
  bytes32 constant SWAPDOMAIN_TYPEHASH = keccak256("Swap(address txOwner,bytes4 functionSelector,uint256 amountIn,uint256 amountOut,address[] path,address to,uint256 nonce,uint256 deadline)");

  constructor(
    address _operator,
    bytes32 _router_domain_seperator
  ) public {
    owner = msg.sender;

    operator = _operator;

    router_domain_seperator = _router_domain_seperator;
    currentRound = 0;
    currentIndex = 0;
  }

  mapping(uint256 => bytes32[]) public txIds;
  
  mapping(uint256 => bytes32[]) public rs;
  mapping(uint256 => bytes32[]) public ss;
  mapping(uint256 => uint8[]) public vs;

  mapping(bytes32 => mapping(address => bool)) public useOfVeto;

  function addRounInfo(bytes32[] calldata _txIds, bytes32[] calldata _rs, bytes32[] calldata _ss, uint8[] calldata _vs) external override {
    txIds[currentRound] = _txIds;

    rs[currentRound] = _rs;
    ss[currentRound] = _ss;
    vs[currentRound] = _vs;
    
    currentIndex = 0;
  }

  function cancelTxId(bytes32 _txId) external override  {
    console.log("Cancel txId");
    console.log(msg.sender);
    console.logBytes32(_txId);
    
    useOfVeto[_txId][msg.sender] = true;
  }

  function validateRoundTxCount(uint256 txCount) external override  view returns (bool) {
    return txIds[currentRound].length <= txCount;
  }

  function validate(Swap.EIP712Swap calldata swap) external override  view returns (bool) {
    console.log("-------");
    console.log("Validate");

    if (ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19\x01",
            router_domain_seperator,
            keccak256(abi.encode(
              SWAPDOMAIN_TYPEHASH,
              swap.txOwner,
              swap.functionSelector,
              swap.amountIn,
              swap.amountOut,
              keccak256(abi.encodePacked(swap.path)),
              swap.to,
              swap.nonce,
              swap.deadline
            ))
          )
        ), 
        vs[currentRound][currentIndex], 
        rs[currentRound][currentIndex], 
        ss[currentRound][currentIndex]
      ) != swap.txOwner ) {
      console.log("false");
      return false;
    }

    console.log(useOfVeto[txIds[currentRound][currentIndex]][swap.txOwner] == false);
    console.log("");

    return useOfVeto[txIds[currentRound][currentIndex]][swap.txOwner] == false;
  }

  function claimValidate(
    uint256 round, 
    uint256 order, 
    bytes32 txId,  
    bytes32 r,
    bytes32 s,
    uint8 v,
    bytes32 proof
  ) external override view returns (bool) {
    if (r != rs[round][order] || 
      s != ss[round][order] || 
      v != vs[round][order] ||
      txIds[round][order] != txId
    ) {
      return false;
    }

    bytes32 orderHash = 0x0000000000000000000000000000000000000000000000000000000000000000;
    for (uint i = 0 ; i < order ; i++) {
      orderHash = keccak256(abi.encodePacked(orderHash, txIds[i]));
    }

    

    return proof == orderHash;
  }

  function goForward() external override  {

    if (txIds[currentRound].length == currentIndex++) {
      currentRound++;
      currentIndex = 0;
    }
  }

  function setOperator(address _operator) public {
    require(msg.sender == owner, "Tex: FORBIDDEN");
    operator = _operator;
  }
}
