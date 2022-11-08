import { ethers } from "hardhat";
import { writeFileSync } from "fs";
import { copySync } from "fs-extra";

async function main() {
  const accounts = await ethers.getSigners();

  const TexRouter02 = await ethers.getContractFactory("TexRouter02");
  const texRouter02 = TexRouter02.attach("0x228eDFeC5F5ee27Fd6B35b01f03BD3b38C4572f0")
  texRouter02.connect(accounts[0])

  await texRouter02.setFeeTo(accounts[0].address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
