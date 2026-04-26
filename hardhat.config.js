require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** 
 * Safe accounts handling for CI
 * Uses default Hardhat test key if PRIVATE_KEY env is set and valid
 * Otherwise uses empty array so compile doesn't crash
 */
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const accounts = PRIVATE_KEY.length === 66 ? [PRIVATE_KEY] : [];

const BASE_SEPOLIA_RPC = process.env.BASE_SEPOLIA_RPC || "https://sepolia.base.org";
const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY || "";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  
  networks: {
    hardhat: {
      // used for local tests
    },
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    baseSepolia: {
      url: BASE_SEPOLIA_RPC,
      accounts: accounts,
      chainId: 84532
    },
    base: {
      url: "https://mainnet.base.org",
      accounts: accounts,
      chainId: 8453
    }
  },

  etherscan: {
    apiKey: {
      baseSepolia: process.env.BASESCAN_API_KEY || "",
      base: process.env.BASESCAN_API_KEY || ""
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org"
        }
      }
    ]
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    coinmarketcap: COINMARKETCAP_API_KEY
  }
};
