require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: "0.8.20",
  networks: {
    riseTestnet: {
      url: "https://testnet.riselabs.xyz",
      chainId: 11155931, // Risechain Testnet Chain ID
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};