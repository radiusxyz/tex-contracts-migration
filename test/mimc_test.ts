import { expect } from "chai"
import { ethers } from "hardhat"

describe("three-sixty", function () {
  it("three-sixty test", async function () {
    const accounts = await ethers.getSigners();

    const Mimc = await ethers.getContractFactory("Mimc");
    const mimc = await Mimc.deploy();

    // mimc.hash([0, 1, 2, 3]);
    const result = await mimc.hash({
      "txOwner": "0x01D5fb852a8107be2cad72dFf64020b22639e18B",
      "functionSelector": "0x375734d9",
      "amountIn": "101",
      "amountOut": "1000000000000000000000",
      "path": [
        "0x01D5fb852a8107be2cad72dFf64020b22639e18B",
        "0x01D5fb852a8107be2cad72dFf64020b22639e18B",
      ],
      "to": "0x01D5fb852a8107be2cad72dFf64020b22639e18B",
      "deadline": "1953105128",
      "nonce": "0"
    });
    // const result = await mimc.hash();

    console.log(result.toHexString())
  })
})