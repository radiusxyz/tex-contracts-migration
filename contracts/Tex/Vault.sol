pragma experimental ABIEncoderV2;
pragma solidity ^0.6.6;

import "hardhat/console.sol";

import "./interfaces/IRecorder.sol";

import "./libraries/Swap.sol";
import "./Mimc.sol";

contract Vault {
  address private owner;
  address public operator;

  Mimc private immutable mimc;  

  bytes32 public router_domain_seperator;
  bytes32 constant CLAIM_TYPEHASH = keccak256("Claim(uint256 round,uint256 order,bytes32 txId,bytes32 proof,bytes32 r,bytes32 s,uint8 v)");

  constructor(
    address _operator,
    bytes32 _router_domain_seperator    
  ) public {
    owner = msg.sender;

    mimc = new Mimc();

    operator = _operator;
    router_domain_seperator = _router_domain_seperator;
  }

  function claim(
    IRecorder recorder,
    address payable msgSender,
    Swap.EIP712Swap memory swap, 
    Swap.TxOrderMsg memory txOrderMsg, 
    Swap.Signature memory operatorSig
  ) public {  
    require(msg.sender == owner, "Tex: FORBIDDEN");
    require(swap.txOwner == msgSender, "Invalid tx owner");

    console.log("claim 1");
    bytes32 txId = mimc.hash(
      swap.txOwner,
      swap.functionSelector,
      swap.amountIn,
      swap.amountOut,
      swap.path,
      swap.to,
      swap.nonce,
      swap.deadline
    );

    console.log("claim 2");
    require(ecrecover(keccak256(
          abi.encodePacked(
            "\x19\x01",
            router_domain_seperator,
            keccak256(abi.encode(
              CLAIM_TYPEHASH,
              txOrderMsg.round,
              txOrderMsg.order,
              txId,
              txOrderMsg.proof,
              txOrderMsg.r,
              txOrderMsg.s,
              txOrderMsg.v
            ))
          )
        ),
        operatorSig.v, 
        operatorSig.r, 
        operatorSig.s
      ) == operator, 
      "invalid operator"
    );
    
    console.log("claim 3");
    require(IRecorder(recorder).claimValidate(
        txOrderMsg.round, 
        txOrderMsg.order, 
        txId, 
        txOrderMsg.r, 
        txOrderMsg.s, 
        txOrderMsg.v, 
        txOrderMsg.proof
      ) == false, 
      "Valid tx order"
    );

    bool sent = msgSender.send(address(this).balance);
    require(sent, "Failed to send");
  }
  
  function deposit() external payable {}

  function setOperator(address _operator) public {
    require(msg.sender == owner, "Tex: FORBIDDEN");
    operator = _operator;
  }
}