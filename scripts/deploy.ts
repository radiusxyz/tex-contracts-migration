import { ethers } from "hardhat";
import { writeFileSync } from "fs";
import { copySync } from "fs-extra";

async function main() {
  const accounts = await ethers.getSigners()
  const deployer = accounts[0]

  const wethAddress = "0xbAfD1699456Fa07681e574B0B30aB1A996e6373e"
  const texFactoryAddress = "0xbAfD1699456Fa07681e574B0B30aB1A996e6373e"

  const TestERC20Factory = await ethers.getContractFactory("TestERC20")
  const RecorderFactory = await (await ethers.getContractFactory("Recorder")).connect(deployer)
  const TexPairFactory = await (await ethers.getContractFactory("TexPair")).connect(deployer)
  const TexFactoryFactory = await ethers.getContractFactory("TexFactory")
  const TexRouter02Factory = await (await ethers.getContractFactory("TexRouter02")).connect(deployer)

  console.log("Modify TexLibrary.sol file if you change something in TexPair.sol");
  console.log("TexPair address:", ethers.utils.solidityKeccak256(["bytes"], [TexPairFactory.bytecode]));

  const recorderContract = await RecorderFactory.deploy()
  await recorderContract.deployed()
  console.log("Recorder contract address: ", recorderContract.address)

  const texRouterContract = await TexRouter02Factory.deploy(recorderContract.address, texFactoryAddress, wethAddress, accounts[0].address, accounts[0].address)
  console.log("Tex router contract address: ", texRouterContract.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
