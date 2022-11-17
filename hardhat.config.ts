import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.4.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
    overrides: {},
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    // hardhat: {
    //   allowUnlimitedContractSize: true
    // },
    optimism_kovan: {
      url: process.env.OPTIMISM_KOVAN_URL || "",
      accounts: [
        process.env.PRIV_KEY0 as any,
        process.env.PRIV_KEY1 as any,
        process.env.PRIV_KEY2 as any,
      ],
    },
    matic_mumbai: {
      url: process.env.MUMBAI_URL || "",
      accounts: [
        process.env.PRIV_KEY0 as any,
        process.env.PRIV_KEY1 as any,
        process.env.PRIV_KEY2 as any,
      ],
    },
    DEV: {
      url: process.env.DEV_URL || "",
      accounts: [
        process.env.PRIV_KEY0 as any,
        process.env.PRIV_KEY1 as any,
        process.env.PRIV_KEY2 as any,
      ],
    },
  },
};

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

export default config;
