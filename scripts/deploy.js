const hre = require("hardhat");

async function main() {
  console.log("Starting deployment to Rise Chain Testnet...");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const riseTokenAddress = process.env.RISE_TOKEN_ADDRESS || "0xd6e1afe5ca8d00a2efc01b89997abe2de47fdfaf";
  
  // 1. Deploy AccessControlManager
  console.log("\n1. Deploying AccessControlManager...");
  const AccessControlManager = await hre.ethers.getContractFactory("AccessControlManager");
  const accessControl = await AccessControlManager.deploy();
  await accessControl.deployed();
  console.log("AccessControlManager deployed to:", accessControl.address);

  // 2. Deploy TokenManager
  console.log("\n2. Deploying TokenManager...");
  const TokenManager = await hre.ethers.getContractFactory("TokenManager");
  const tokenManager = await TokenManager.deploy(riseTokenAddress, accessControl.address);
  await tokenManager.deployed();
  console.log("TokenManager deployed to:", tokenManager.address);

  // 3. Deploy HorseRegistry
  console.log("\n3. Deploying HorseRegistry...");
  const HorseRegistry = await hre.ethers.getContractFactory("HorseRegistry");
  const horseRegistry = await HorseRegistry.deploy(accessControl.address);
  await horseRegistry.deployed();
  console.log("HorseRegistry deployed to:", horseRegistry.address);

  // 4. Deploy PowerUpSystem
  console.log("\n4. Deploying PowerUpSystem...");
  const PowerUpSystem = await hre.ethers.getContractFactory("PowerUpSystem");
  const powerUpSystem = await PowerUpSystem.deploy(accessControl.address, tokenManager.address);
  await powerUpSystem.deployed();
  console.log("PowerUpSystem deployed to:", powerUpSystem.address);

  // 5. Deploy BettingPool
  console.log("\n5. Deploying BettingPool...");
  const BettingPool = await hre.ethers.getContractFactory("BettingPool");
  const bettingPool = await BettingPool.deploy(accessControl.address, tokenManager.address);
  await bettingPool.deployed();
  console.log("BettingPool deployed to:", bettingPool.address);

  // 6. Deploy RaceEngine
  console.log("\n6. Deploying RaceEngine...");
  const RaceEngine = await hre.ethers.getContractFactory("RaceEngine");
  const raceEngine = await RaceEngine.deploy(accessControl.address, horseRegistry.address, powerUpSystem.address);
  await raceEngine.deployed();
  console.log("RaceEngine deployed to:", raceEngine.address);

  // 7. Deploy RaceManager
  console.log("\n7. Deploying RaceManager...");
  const RaceManager = await hre.ethers.getContractFactory("RaceManager");
  const raceManager = await RaceManager.deploy(
    accessControl.address,
    tokenManager.address,
    horseRegistry.address,
    powerUpSystem.address,
    bettingPool.address,
    raceEngine.address
  );
  await raceManager.deployed();
  console.log("RaceManager deployed to:", raceManager.address);

  // 8. Setup permissions
  console.log("\n8. Setting up permissions...");
  
  // Grant RaceManager role to the main contract
  await accessControl.grantRaceManagerRole(raceManager.address);
  console.log("Granted RaceManager role to:", raceManager.address);

  // Summary
  console.log("\n=== DEPLOYMENT SUMMARY ===");
  console.log("Network: Rise Chain Testnet");
  console.log("Chain ID: 11155931");
  console.log("RISE Token:", riseTokenAddress);
  console.log("\nContract Addresses:");
  console.log("AccessControlManager:", accessControl.address);
  console.log("TokenManager:", tokenManager.address);
  console.log("HorseRegistry:", horseRegistry.address);
  console.log("PowerUpSystem:", powerUpSystem.address);
  console.log("BettingPool:", bettingPool.address);
  console.log("RaceEngine:", raceEngine.address);
  console.log("RaceManager:", raceManager.address);
  
  console.log("\n=== NEXT STEPS ===");
  console.log("1. Get RISE tokens from faucet: https://faucet.testnet.riselabs.xyz");
  console.log("2. Approve RISE tokens for contracts");
  console.log("3. Create your first race using RaceManager.createRace()");
  console.log("4. Test betting and power-up features");
  
  // Save deployment addresses to file
  const fs = require('fs');
  const deploymentAddresses = {
    network: "riseTestnet",
    chainId: 11155931,
    riseToken: riseTokenAddress,
    contracts: {
      accessControl: accessControl.address,
      tokenManager: tokenManager.address,
      horseRegistry: horseRegistry.address,
      powerUpSystem: powerUpSystem.address,
      bettingPool: bettingPool.address,
      raceEngine: raceEngine.address,
      raceManager: raceManager.address
    }
  };
  
  fs.writeFileSync(
    './deployments.json',
    JSON.stringify(deploymentAddresses, null, 2)
  );
  console.log("\nDeployment addresses saved to deployments.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });