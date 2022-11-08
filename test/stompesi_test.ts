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
    const TexFactoryFactory = await ethers.getContractFactory("TexFactory")
    const TexRouter02Factory = await ethers.getContractFactory("TexRouter02")

    const recorderContract = await RecorderFactory.deploy()
    await recorderContract.deployed()
    console.log("recorderContract is deployed")

    const factoryContract = await TexFactoryFactory.deploy(signerAddress)
    await factoryContract.deployed()
    console.log("factoryContract is deployed")

    const wethContract = await TestERC20Factory.deploy("Wrapped Ether", "WETH", ethers.utils.parseUnits("1000000", 18))
    await wethContract.deployed()
    console.log("wethContract is deployed")

    const routerContract = await TexRouter02Factory.deploy(
      recorderContract.address,
      factoryContract.address,
      wethContract.address,
      signerAddress,
      signerAddress, {
      gasLimit: 10000000
    }
    )
    await routerContract.deployed()
    console.log("routerContract is deployed")

    await routerContract.setFeeTo(accounts[1].address);

    let aTokenContract = await TestERC20Factory.deploy("A token", "A_TOKEN", ethers.utils.parseUnits("1000000", 18))
    await aTokenContract.deployed()

    const bTokenContract = await TestERC20Factory.deploy("B token", "B_TOKEN", ethers.utils.parseUnits("1000000", 18))
    await bTokenContract.deployed()

    const result = await factoryContract.createPair(aTokenContract.address, bTokenContract.address)
    await result.wait()

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

    const txIds: any = []
    const txs: any = []
    const vs: any = []
    const rs: any = []
    const ss: any = []
    for (let i = 1; i <= userCount; i++) {
      const client = clients[i]
      aTokenContract = await aTokenContract.connect(client.signer);

      if (i !== 13 && i !== 16) {
        const approveResult = await aTokenContract.approve(routerContract.address, ethers.utils.parseUnits("1000000", 18))
        await approveResult.wait()
      }

      const tx = {
        txOwner: client.address,
        functionSelector: "0x375734d9",
        amountIn: ethers.utils.parseUnits("1", 18),
        amountOut: "0",
        path: [
          aTokenContract.address,
          bTokenContract.address,
        ],
        to: client.address,
        nonce: "0",
        deadline: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 2
      }

      const txId = ethers.utils.solidityKeccak256(
        ['address', 'bytes4', 'uint256', 'uint256', 'address[]', 'address', 'uint256', 'uint256'],
        [tx.txOwner, tx.functionSelector, tx.amountIn, tx.amountOut, tx.path, tx.to, tx.nonce, tx.deadline],
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

      const signatureHex = await client.signer._signTypedData(typedData.domain, { Swap: typedData.types.Swap }, tx)
      const signature = ethers.utils.splitSignature(signatureHex)
      const aTokenName = await aTokenContract.name()
      const aTokenBalance = await aTokenContract.balanceOf(client.address)
      const aTokenAllowance = await aTokenContract.allowance(client.address, routerContract.address)

      // console.log(`${client.address} / ${aTokenName} balance: ${aTokenBalance}`)
      // console.log(`${aTokenName} approve: client -> router: ${aTokenAllowance}`)
      txIds.push(txId)
      txs.push(tx)
      vs.push(signature.v)
      rs.push(signature.r)
      ss.push(signature.s)
    }

    const addTxIdsResult = await recorderContract.addTxIds(txIds)
    await addTxIdsResult.wait()

    const batchSwapResult = await routerContract.batchSwap(txs, vs, rs, ss, { gasLimit: 10000000 })
    await batchSwapResult.wait()

    for (let i = 1; i <= userCount; i++) {
      const client = clients[i]
      const bTokenBalance = await bTokenContract.balanceOf(client.address)

      console.log(bTokenBalance)
    }


    console.log(batchSwapResult.hash)
  })
})