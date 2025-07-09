import "@nomicfoundation/hardhat-toolbox";
import { HardhatUserConfig } from "hardhat/config";
import * as dotenv from "dotenv";

import "./tasks/deploy";
import "@zetachain/localnet/tasks";
import "@zetachain/toolkit/tasks";
import { getHardhatConfig } from "@zetachain/toolkit/client";

dotenv.config();

const baseSepolia = {
  url: "https://sepolia.base.org",
  chainId: 84532,
  accounts: [process.env.PRIVATE_KEY as string],
};

const config: HardhatUserConfig = {
  ...getHardhatConfig({ accounts: [process.env.PRIVATE_KEY] }),
  
  networks: {
    ...getHardhatConfig({ accounts: [process.env.PRIVATE_KEY as string] }).networks,
    baseSepolia,
  },

  etherscan: {
    apiKey: {
      baseSepolia: process.env.BASESCAN_API_KEY as string,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },
};

export default config;
