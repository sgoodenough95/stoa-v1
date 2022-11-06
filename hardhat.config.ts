import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.17",
  networks: {
    mumbai: {
      url: "https://polygon-mumbai.infura.io/v3/8a810c64d6c94917bc699bb048e191a9",
      accounts: ["54fec71996ee5cb340b6ee5a674c637fa3089898199fc89758a7f5aaea2f3df6"]
    }
  }
};

export default config;