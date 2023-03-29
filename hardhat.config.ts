import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from 'dotenv';

dotenv.config()

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      gas: 12000000,
      blockGasLimit: 0x1fffffffffffff,
      allowUnlimitedContractSize: true,
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      accounts: [process.env.PRIVATE_KEY || ''],
    },
    mainnet: {
      url: "https://bsc-dataseed.binance.org/",
      accounts: [process.env.PRIVATE_KEY || '']
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.10",
      },
      {
        version: "0.4.18",
      },
      {
        version: "0.5.16",
      },
      {
        version: "0.6.6",
      },
      {
        version: "0.6.12",
      },
    ]
  },
  etherscan: {
    apiKey: "P3YT3GEZI9SFNR7C8A5ZVEGXDADJEPFJZF"
  }
};

export default config;
