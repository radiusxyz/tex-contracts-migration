pragma experimental ABIEncoderV2;
pragma solidity >=0.5.0;

import "../libraries/Swap.sol";

interface IRecorder {
  function addRounInfo(bytes32[] calldata _txIds, bytes32[] calldata _rs, bytes32[] calldata _ss, uint8[] calldata _vs) external;
  function cancelTxId(bytes32 _txId) external;
  function validateRoundTxCount(uint256 txCount) external view returns (bool);
  function validate(Swap.EIP712Swap calldata swap) external view returns (bool);
  function claimValidate(uint256 round,  uint256 order,  bytes32 txId,  bytes32 r, bytes32 s, uint8 v, bytes32 proof) external view returns (bool);

  function goForward() external;
}
