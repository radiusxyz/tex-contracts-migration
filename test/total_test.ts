import { expect } from "chai"
import { ethers } from "hardhat"

describe("three-sixty", function () {
  it("three-sixty test", async function () {
    const accounts = await ethers.getSigners()
    const signer = accounts[0]
    const signerAddress = accounts[0].address

    const clients = []
    const userCount = 16
    for (let i = 1; i <= userCount; i++) {
      clients[i] = {
        signer: accounts[i],
        address: accounts[i].address,
      }
    }

    const TestERC20Factory = await ethers.getContractFactory("TestERC20")
    const RecorderFactory = await ethers.getContractFactory("Recorder")
    // const VaultFactory = await ethers.getContractFactory("Vault")
    const MimcFactory = await ethers.getContractFactory("Mimc")
    const TexFactoryFactory = await ethers.getContractFactory("TexFactory")
    const TexRouter02Factory = await ethers.getContractFactory("TexRouter02")

    const mimc = await MimcFactory.deploy();

    const factoryContract = await TexFactoryFactory.deploy(signerAddress)
    await factoryContract.deployed()

    const wethContract = await TestERC20Factory.deploy("Wrapped Ether", "WETH", ethers.utils.parseUnits("1000000", 18))
    await wethContract.deployed()

    const recorderContract = await RecorderFactory.deploy()
    await recorderContract.deployed()

    const routerContract = await TexRouter02Factory.deploy(
      recorderContract.address,
      factoryContract.address,
      wethContract.address,
      signerAddress,
      signerAddress, {
      gasLimit: "10000000"
    }
    )
    await routerContract.deployed()

    const setOperatorResult = await routerContract.setOperator(signerAddress)
    setOperatorResult.wait()
    // const vaultContract = VaultFactory.attach(await routerContract.vault())

    // const depositResult = await vaultContract.deposit({ value: ethers.utils.parseEther("1.0") })
    // await depositResult.wait()

    // let contractBalance = await ethers.provider.getBalance(vaultContract.address)

    await routerContract.setFeeTo(accounts[1].address);

    let aTokenContract = await TestERC20Factory.deploy("A token", "A_TOKEN", ethers.utils.parseUnits("1000000", 18))
    await aTokenContract.deployed()

    const bTokenContract = await TestERC20Factory.deploy("B token", "B_TOKEN", ethers.utils.parseUnits("1000000", 18))
    await bTokenContract.deployed()

    const result = await factoryContract.createPair(aTokenContract.address, bTokenContract.address)
    await result.wait()
    const pairContractAddress = await factoryContract.getPair(aTokenContract.address, bTokenContract.address);


    const approveATokenResult = await aTokenContract.approve(routerContract.address, ethers.utils.parseUnits("1000000", 18))
    await approveATokenResult.wait()

    const approveBTokenResult = await bTokenContract.approve(routerContract.address, ethers.utils.parseUnits("1000000", 18))
    await approveBTokenResult.wait()

    const addLiquidityResult = await routerContract.addLiquidity(
      aTokenContract.address,
      bTokenContract.address,
      ethers.utils.parseUnits("500", 18),
      ethers.utils.parseUnits("500", 18),
      "0",
      "0",
      signerAddress,
      Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 2,
    )
    await addLiquidityResult.wait()

    for (let i = 1; i <= userCount; i++) {
      const client = clients[i]

      const transferResult = await aTokenContract.transfer(client.address, ethers.utils.parseUnits("500", 18))
      await transferResult.wait()
    }

    const txHashes: any = []
    const txs: any = []

    const rs: any = []
    const ss: any = []
    const vs: any = []

    let txOrderMsg: any
    let operatorSig: any
    let claimTx: any
    let hash = "0x0000000000000000000000000000000000000000000000000000000000000000"

    for (let i = 1; i <= userCount; i++) {
      const client = clients[i]
      aTokenContract = await aTokenContract.connect(client.signer);

      if (i !== 13 && i !== 16) {
        const approveResult = await aTokenContract.approve(routerContract.address, ethers.utils.parseUnits("1000000", 18))
        await approveResult.wait()
      } else {
        console.log(i, "번째 사용자 approve 하지않음 (approve가 없어서 swap이 되지 않음)")
      }

      const tx = {
        txOwner: client.address,
        functionSelector: "0x375734d9",
        amountIn: "100000000000000",
        amountOut: "0",
        path: [
          aTokenContract.address,
          bTokenContract.address,
        ],
        to: client.address,
        nonce: "0",
        // deadline: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 2
        deadline: 1968845350
      }

      const mimcHash = await mimc.hash(
        tx.txOwner,
        tx.functionSelector,
        tx.amountIn,
        tx.amountOut,
        tx.path,
        tx.to,
        tx.nonce,
        tx.deadline
      )

      hash = ethers.utils.solidityKeccak256(
        ['bytes32', 'bytes32'],
        [hash, mimcHash],
      )

      const typedData = {
        types: {
          EIP712Domain: [
            { name: 'name', type: 'string' },
            { name: 'version', type: 'string' },
            { name: 'chainId', type: 'uint256' },
            { name: 'verifyingContract', type: 'address' },
          ],
          Swap: [
            { name: 'txOwner', type: 'address' },
            { name: 'functionSelector', type: 'bytes4' },
            { name: 'amountIn', type: 'uint256' },
            { name: 'amountOut', type: 'uint256' },
            { name: 'path', type: 'address[]' },
            { name: 'to', type: 'address' },
            { name: 'nonce', type: 'uint256' },
            { name: 'deadline', type: 'uint256' },
          ],
        },
        primaryType: 'Swap',
        domain: {
          name: 'Tex swap',
          version: '1',
          chainId: 80001,
          verifyingContract: routerContract.address,
        },
      }

      const txHash = ethers.utils._TypedDataEncoder.hash(typedData.domain, { Swap: typedData.types.Swap }, tx)
      const signatureHex = await client.signer._signTypedData(typedData.domain, { Swap: typedData.types.Swap }, tx)

      // console.log(signatureHex)
      const userSig = ethers.utils.splitSignature(signatureHex)
      // console.log("verifyMessage", ethers.utils.recoverAddress(txHash, userSig), tx.txOwner, client.address)

      if (i == 1) {
        claimTx = JSON.parse(JSON.stringify(tx))

        const typedData = {
          types: {
            EIP712Domain: [
              { name: 'name', type: 'string' },
              { name: 'version', type: 'string' },
              { name: 'chainId', type: 'uint256' },
              { name: 'verifyingContract', type: 'address' },
            ],
            Claim: [
              { name: 'round', type: 'uint256' },
              { name: 'order', type: 'uint256' },
              { name: 'mimcHash', type: 'bytes32' },
              { name: 'txHash', type: 'bytes32' },
              { name: 'proofHash', type: 'bytes32' }
            ],
          },
          primaryType: 'Claim',
          domain: {
            name: 'Tex swap',
            version: '1',
            chainId: 80001,
            verifyingContract: routerContract.address,
          },
        }

        txOrderMsg = {
          round: 0,
          order: i,
          mimcHash: mimcHash,
          txHash: txHash,
          proofHash: hash
        }


        const signatureHex = await signer._signTypedData(typedData.domain, { Claim: typedData.types.Claim }, txOrderMsg)
        operatorSig = ethers.utils.splitSignature(signatureHex)


        userSig.v = 3
        console.log(i, "번째 사용자 서명값 변경 (악의적인 오퍼레이터)")
      }

      if (i == 3) {

        const userRecorderContract = RecorderFactory.connect(client.signer).attach(await routerContract.recorder())

        console.log(i, "번째 사용자 disableTxHash")
        const disableTxHashResult = await userRecorderContract.disableTxHash(txHash)
        await disableTxHashResult.wait()
      }
      txHashes.push(txHash)
      txs.push(tx)
      rs.push(userSig.r)
      ss.push(userSig.s)
      vs.push(userSig.v)
    }

    console.log("")
    console.log("addTxHashes")
    const addTxIdsResult = await recorderContract.addTxHashes(txHashes)
    await addTxIdsResult.wait()

    console.log("Start batchSwap")
    const batchSwapResult = await routerContract.batchSwap(txs, vs, rs, ss, { gasLimit: 10000000 })
    await batchSwapResult.wait()

    console.log("")
    console.log("잔고조회")
    for (let i = 1; i <= userCount; i++) {
      const client = clients[i]
      const bTokenBalance = await bTokenContract.balanceOf(client.address)

      console.log(i, "번째 사용자 : ", bTokenBalance.toString())
    }

    const userRouterContract = TexRouter02Factory.connect(clients[1].signer).attach(routerContract.address)

    console.log("claimTx")
    const claimTxIdResult = await userRouterContract.claim(
      txOrderMsg.round,
      txOrderMsg.order,
      txOrderMsg.proofHash,
      claimTx,
      operatorSig.v,
      operatorSig.r,
      operatorSig.s
    )
    await claimTxIdResult.wait()
    console.log("claim 성공")

    // contractBalance = await ethers.provider.getBalance(vaultContract.address)
    // const userBalance = await ethers.provider.getBalance(clients[1].address)

    // console.log("contractBalance", contractBalance)
    // console.log("userBalance", userBalance)

  })
})