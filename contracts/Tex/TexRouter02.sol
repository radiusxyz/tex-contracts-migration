pragma experimental ABIEncoderV2;
pragma solidity ^0.6.6;

import "hardhat/console.sol";

import "./interfaces/ITexFactory.sol";
import "./libraries/TransferHelper.sol";

import "./interfaces/ITexRouter02.sol";
import "./libraries/TexLibrary.sol";
import "./libraries/SafeMath.sol";

import "./libraries/Swap.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

import "./Recorder.sol";
import "./Vault.sol";

contract TexRouter02 is ITexRouter02 {
  using SafeMath for uint256;
  address public immutable override factory;
  address public immutable override WETH;
  
  Recorder public immutable recorder;
  Vault public immutable vault;

  address public feeTo;
  address public feeToSetter;

  address public operator;
  address public operatorSetter;

  event Invalid(uint256 round, uint256 index, uint8 validationType);
  event SwapEvent(uint256 round, uint256 index, bool success);
  mapping(address => uint256) public nonces;

  bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

  modifier ensure(uint256 deadline) {
    require(deadline >= block.timestamp, "TexRouter: EXPIRED");
    _;
  }

  constructor(
    address _factory,
    address _WETH,
    address _feeToSetter,
    address _operatorSetter
  ) public {
    factory = _factory;
    WETH = _WETH;

    feeToSetter = _feeToSetter;
    feeTo = msg.sender;

    operatorSetter = _operatorSetter;
    operator = msg.sender;

    bytes32 DOMAIN_SEPARATOR = keccak256(abi.encode(
      EIP712DOMAIN_TYPEHASH,
      keccak256(bytes("Tex swap")),
      keccak256(bytes("1")),
      80001,
      address(this)
    ));  

    recorder = new Recorder(msg.sender, DOMAIN_SEPARATOR);    
    vault = new Vault(msg.sender, DOMAIN_SEPARATOR);
  }

  receive() external payable {
    assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
  }

  function claim(
    Swap.EIP712Swap memory swap, 
    Swap.TxOrderMsg memory txOrderMsg, 
    Swap.Signature memory operatorSig
  ) public {
    vault.claim(recorder, msg.sender, swap, txOrderMsg, operatorSig);
  }

  function setFeeTo(address _feeTo) external {
    require(msg.sender == feeToSetter, "Tex: FORBIDDEN");
    feeTo = _feeTo;
  }

  function setFeeToSetter(address _feeToSetter) external {
    require(msg.sender == feeToSetter, "Tex: FORBIDDEN");
    feeToSetter = _feeToSetter;
  }

  function setOperator(address _operator) external {
    require(msg.sender == operatorSetter, "Tex: FORBIDDEN");
    operator = _operator;
    recorder.setOperator(_operator);
    vault.setOperator(_operator);
  }

  function setOperatorSetter(address _operatorSetter) external {
    require(msg.sender == operatorSetter, "Tex: FORBIDDEN");
    operatorSetter = _operatorSetter;
  }

  // **** ADD LIQUIDITY ****
  function _addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin
  ) internal virtual returns (uint256 amountA, uint256 amountB) {
    // create the pair if it doesn't exist yet
    if (ITexFactory(factory).getPair(tokenA, tokenB) == address(0)) {
      ITexFactory(factory).createPair(tokenA, tokenB);
    }
    (uint256 reserveA, uint256 reserveB) = TexLibrary.getReserves(factory, tokenA, tokenB);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = TexLibrary.quote(
        amountADesired,
        reserveA,
        reserveB
      );
      if (amountBOptimal <= amountBDesired) {
        require(
          amountBOptimal >= amountBMin,
          "TexRouter: INSUFFICIENT_B_AMOUNT"
        );
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = TexLibrary.quote(
          amountBDesired,
          reserveB,
          reserveA
        );
        assert(amountAOptimal <= amountADesired);
        require(
          amountAOptimal >= amountAMin,
          "TexRouter: INSUFFICIENT_A_AMOUNT"
        );
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  )
    external
    virtual
    override
    ensure(deadline)
    returns (
      uint256 amountA,
      uint256 amountB,
      uint256 liquidity
    )
  {
    (amountA, amountB) = _addLiquidity(
      tokenA,
      tokenB,
      amountADesired,
      amountBDesired,
      amountAMin,
      amountBMin
    );
    address pair = TexLibrary.pairFor(factory, tokenA, tokenB);
    TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
    TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
    liquidity = ITexPair(pair).mint(to);
  }

  function addLiquidityETH(
    address token,
    uint256 amountTokenDesired,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  )
    external
    payable
    virtual
    override
    ensure(deadline)
    returns (
      uint256 amountToken,
      uint256 amountETH,
      uint256 liquidity
    )
  {
    (amountToken, amountETH) = _addLiquidity(
      token,
      WETH,
      amountTokenDesired,
      msg.value,
      amountTokenMin,
      amountETHMin
    );
    address pair = TexLibrary.pairFor(factory, token, WETH);
    TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
    IWETH(WETH).deposit{ value: amountETH }();
    assert(IWETH(WETH).transfer(pair, amountETH));
    liquidity = ITexPair(pair).mint(to);
    // refund dust eth, if any
    if (msg.value > amountETH)
      TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
  }

  // **** REMOVE LIQUIDITY ****
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  )
    public
    virtual
    override
    ensure(deadline)
    returns (uint256 amountA, uint256 amountB)
  {
    address pair = TexLibrary.pairFor(factory, tokenA, tokenB);
    ITexPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
    (uint256 amount0, uint256 amount1) = ITexPair(pair).burn(to);
    (address token0, ) = TexLibrary.sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0
      ? (amount0, amount1)
      : (amount1, amount0);
    require(amountA >= amountAMin, "TexRouter: INSUFFICIENT_A_AMOUNT");
    require(amountB >= amountBMin, "TexRouter: INSUFFICIENT_B_AMOUNT");
  }

  function removeLiquidityETH(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  )
    public
    virtual
    override
    ensure(deadline)
    returns (uint256 amountToken, uint256 amountETH)
  {
    (amountToken, amountETH) = removeLiquidity(
      token,
      WETH,
      liquidity,
      amountTokenMin,
      amountETHMin,
      address(this),
      deadline
    );
    TransferHelper.safeTransfer(token, to, amountToken);
    IWETH(WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityWithPermit(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (uint256 amountA, uint256 amountB) {
    address pair = TexLibrary.pairFor(factory, tokenA, tokenB);
    uint256 value = approveMax ? uint256(-1) : liquidity;
    ITexPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountA, amountB) = removeLiquidity(
      tokenA,
      tokenB,
      liquidity,
      amountAMin,
      amountBMin,
      to,
      deadline
    );
  }

  function removeLiquidityETHWithPermit(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
    address pair = TexLibrary.pairFor(factory, token, WETH);
    uint256 value = approveMax ? uint256(-1) : liquidity;
    ITexPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountToken, amountETH) = removeLiquidityETH(
      token,
      liquidity,
      amountTokenMin,
      amountETHMin,
      to,
      deadline
    );
  }

  // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
  function removeLiquidityETHSupportingFeeOnTransferTokens(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline
  ) public virtual override ensure(deadline) returns (uint256 amountETH) {
    (, amountETH) = removeLiquidity(
      token,
      WETH,
      liquidity,
      amountTokenMin,
      amountETHMin,
      address(this),
      deadline
    );
    TransferHelper.safeTransfer(
      token,
      to,
      IERC20(token).balanceOf(address(this))
    );
    IWETH(WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    address token,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountETHMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (uint256 amountETH) {
    address pair = TexLibrary.pairFor(factory, token, WETH);
    uint256 value = approveMax ? uint256(-1) : liquidity;
    ITexPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
      token,
      liquidity,
      amountTokenMin,
      amountETHMin,
      to,
      deadline
    );
  }

  // **** SWAP ****
  // requires the initial amount to have already been sent to the first pair
  function _swap(
    uint256[] memory amounts,
    address[] memory path,
    address _to
  ) internal virtual {
    for (uint256 i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0, ) = TexLibrary.sortTokens(input, output);
      uint256 amountOut = amounts[i + 1];
      (uint256 amount0Out, uint256 amount1Out) = input == token0
        ? (uint256(0), amountOut)
        : (amountOut, uint256(0));
      address to = i < path.length - 2
        ? TexLibrary.pairFor(factory, output, path[i + 2])
        : _to;
      ITexPair(TexLibrary.pairFor(factory, input, output)).swap(
        amount0Out,
        amount1Out,
        to,
        new bytes(0)
      );
    }
  }
  
  function batchSwap(
    Swap.EIP712Swap[] memory swaps
  ) public {
    require(address(vault).balance >= 1000000000000000000, "Insufficient deposit");
    require(recorder.validateRoundTxCount(swaps.length), "Invalid tx count");

    for (uint256 i = 0; i < swaps.length; i++) {
      bool success = false;
      if (recorder.validate(swaps[i]) && (swaps[i].nonce == nonces[swaps[i].txOwner]++)) {
        if(swaps[i].functionSelector == 0x375734d9) {
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapExactTokensForTokens(address,uint256,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountIn,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0x22b58410){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapTokensForExactTokens(address,uint256,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountIn,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0x7ff36ab5){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapExactETHForTokens(uint256,address[],address,uint256)",
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0xfa3219d5){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapTokensForExactETH(address,uint256,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountIn,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0x9c91fcb5){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapExactTokensForETH(address,uint256,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountIn,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0xb05f579e){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapETHForExactTokens(address,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0xb1ca4936){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapExactTokensForTokensSupportingFeeOnTransferTokens(address,uint256,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountIn,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        } else if(swaps[i].functionSelector == 0x5cae0310){
          (success,) = address(this).delegatecall(
            abi.encodeWithSignature(
              "swapExactTokensForETHSupportingFeeOnTransferTokens(address,uint256,uint256,address[],address,uint256)",
              swaps[i].txOwner,
              swaps[i].amountIn,
              swaps[i].amountOut,
              swaps[i].path,
              swaps[i].to,
              swaps[i].deadline
            )
          );
        }
      } 
      emit SwapEvent(recorder.currentRound(), i, success);
      recorder.goForward();
    }
  }

  function swapExactTokensForTokens(
    address sender,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  )
    external
    virtual
    override
    ensure(deadline)
    returns (uint256[] memory amounts)
{
    uint256 feeAmount = amountIn / 2000;
    amounts = TexLibrary.getAmountsOut(factory, amountIn - feeAmount, path);

    require(
      amounts[amounts.length - 1] >= amountOutMin,
      "INSUFFICIENT_OUTPUT_AMOUNT"
    );   
    
    console.log("swapExactTokensForTokens");
    console.log("tx sender", sender);
    console.log("fee to", feeTo);

    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      feeTo,
      feeAmount
    );
    console.log("swapExactTokensForTokens - complete to send fee");

    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      TexLibrary.pairFor(factory, path[0], path[1]),
      amounts[0]
    );
    console.log("swapExactTokensForTokens - complete to send coin to pair");
    
    _swap(amounts, path, to);
    console.log("swapExactTokensForTokens - complete to swap");
    console.log("");
  }

  function swapTokensForExactTokens(
    address sender,
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  )
    external
    virtual
    override
    ensure(deadline)
    returns (uint256[] memory amounts)
  {
    amounts = TexLibrary.getAmountsIn(factory, amountOut, path);
    require(amounts[0] <= amountInMax, "TexRouter: EXCESSIVE_INPUT_AMOUNT");
    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      TexLibrary.pairFor(factory, path[0], path[1]),
      amounts[0]
    );
    _swap(amounts, path, to);
  }

  function swapExactETHForTokens(
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  )
    external
    payable
    virtual
    override
    ensure(deadline)
    returns (uint256[] memory amounts)
  {
    require(path[0] == WETH, "TexRouter: INVALID_PATH");
    amounts = TexLibrary.getAmountsOut(factory, msg.value, path);
    require(
      amounts[amounts.length - 1] >= amountOutMin,
      "TexRouter: INSUFFICIENT_OUTPUT_AMOUNT"
    );
    IWETH(WETH).deposit{ value: amounts[0] }();
    assert(
      IWETH(WETH).transfer(
        TexLibrary.pairFor(factory, path[0], path[1]),
        amounts[0]
      )
    );
    _swap(amounts, path, to);
  }

  function swapTokensForExactETH(
    address sender,
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  )
    external
    virtual
    override
    ensure(deadline)
    returns (uint256[] memory amounts)
  {
    require(path[path.length - 1] == WETH, "TexRouter: INVALID_PATH");
    amounts = TexLibrary.getAmountsIn(factory, amountOut, path);
    require(amounts[0] <= amountInMax, "TexRouter: EXCESSIVE_INPUT_AMOUNT");
    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      TexLibrary.pairFor(factory, path[0], path[1]),
      amounts[0]
    );
    _swap(amounts, path, address(this));
    IWETH(WETH).withdraw(amounts[amounts.length - 1]);
    TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
  }

  function swapExactTokensForETH(
    address sender,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  )
    external
    virtual
    override
    ensure(deadline)
    returns (uint256[] memory amounts)
  {
    require(path[path.length - 1] == WETH, "TexRouter: INVALID_PATH");
    amounts = TexLibrary.getAmountsOut(factory, amountIn, path);
    require(
      amounts[amounts.length - 1] >= amountOutMin,
      "TexRouter: INSUFFICIENT_OUTPUT_AMOUNT"
    );
    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      TexLibrary.pairFor(factory, path[0], path[1]),
      amounts[0]
    );
    _swap(amounts, path, address(this));
    IWETH(WETH).withdraw(amounts[amounts.length - 1]);
    TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
  }

  function swapETHForExactTokens(
    address sender,
    uint256 amountOut,
    address[] calldata path,
    address to,
    uint256 deadline
  )
    external
    payable
    virtual
    override
    ensure(deadline)
    returns (uint256[] memory amounts)
  {
    require(path[0] == WETH, "TexRouter: INVALID_PATH");
    amounts = TexLibrary.getAmountsIn(factory, amountOut, path);
    require(amounts[0] <= msg.value, "TexRouter: EXCESSIVE_INPUT_AMOUNT");
    IWETH(WETH).deposit{ value: amounts[0] }();
    assert(
      IWETH(WETH).transfer(
        TexLibrary.pairFor(factory, path[0], path[1]),
        amounts[0]
      )
    );
    _swap(amounts, path, to);
    // refund dust eth, if any
    if (msg.value > amounts[0])
      TransferHelper.safeTransferETH(sender, msg.value - amounts[0]);
  }

  // **** SWAP (supporting fee-on-transfer tokens) ****
  // requires the initial amount to have already been sent to the first pair
  function _swapSupportingFeeOnTransferTokens(
    address[] memory path,
    address _to
  ) internal virtual {
    for (uint256 i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0, ) = TexLibrary.sortTokens(input, output);
      ITexPair pair = ITexPair(TexLibrary.pairFor(factory, input, output));
      uint256 amountInput;
      uint256 amountOutput;
      {
        // scope to avoid stack too deep errors
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        (uint256 reserveInput, uint256 reserveOutput) = input == token0
          ? (reserve0, reserve1)
          : (reserve1, reserve0);
        amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = TexLibrary.getAmountOut(
          amountInput,
          reserveInput,
          reserveOutput
        );
      }
      (uint256 amount0Out, uint256 amount1Out) = input == token0
        ? (uint256(0), amountOutput)
        : (amountOutput, uint256(0));
      address to = i < path.length - 2
        ? TexLibrary.pairFor(factory, output, path[i + 2])
        : _to;
      pair.swap(amount0Out, amount1Out, to, new bytes(0));
    }
  }

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    address sender,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) {
    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      TexLibrary.pairFor(factory, path[0], path[1]),
      amountIn
    );
    uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to);
    require(
      IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >=
        amountOutMin,
      "TexRouter: INSUFFICIENT_OUTPUT_AMOUNT"
    );
  }

  function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external payable virtual override ensure(deadline) {
    require(path[0] == WETH, "TexRouter: INVALID_PATH");
    uint256 amountIn = msg.value;
    IWETH(WETH).deposit{ value: amountIn }();
    assert(
      IWETH(WETH).transfer(
        TexLibrary.pairFor(factory, path[0], path[1]),
        amountIn
      )
    );
    uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to);
    require(
      IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >=
        amountOutMin,
      "TexRouter: INSUFFICIENT_OUTPUT_AMOUNT"
    );
  }

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    address sender,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external virtual override ensure(deadline) {
    require(path[path.length - 1] == WETH, "TexRouter: INVALID_PATH");
    TransferHelper.safeTransferFrom(
      path[0],
      sender,
      TexLibrary.pairFor(factory, path[0], path[1]),
      amountIn
    );
    _swapSupportingFeeOnTransferTokens(path, address(this));
    uint256 amountOut = IERC20(WETH).balanceOf(address(this));
    require(amountOut >= amountOutMin, "TexRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    IWETH(WETH).withdraw(amountOut);
    TransferHelper.safeTransferETH(to, amountOut);
  }

  // **** LIBRARY FUNCTIONS ****
  function quote(
    uint256 amountA,
    uint256 reserveA,
    uint256 reserveB
  ) public pure virtual override returns (uint256 amountB) {
    return TexLibrary.quote(amountA, reserveA, reserveB);
  }

  function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
  ) public pure virtual override returns (uint256 amountOut) {
    return TexLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
  }

  function getAmountIn(
    uint256 amountOut,
    uint256 reserveIn,
    uint256 reserveOut
  ) public pure virtual override returns (uint256 amountIn) {
    return TexLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
  }

  function getAmountsOut(uint256 amountIn, address[] memory path)
    public
    view
    virtual
    override
    returns (uint256[] memory amounts)
  {
    return TexLibrary.getAmountsOut(factory, amountIn, path);
  }

  function getAmountsIn(uint256 amountOut, address[] memory path)
    public
    view
    virtual
    override
    returns (uint256[] memory amounts)
  {
    return TexLibrary.getAmountsIn(factory, amountOut, path);
  }
}