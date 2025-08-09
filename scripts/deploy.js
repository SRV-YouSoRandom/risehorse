const { ethers } = require("hardhat");

async function main() {
  console.log("Starting deployment to Rise Chain Testnet...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const riseTokenAddress = process.env.RISE_TOKEN_ADDRESS || "0xd6e1afe5ca8d00a2efc01b89997abe2de47fdfaf";
  
  // 1. Deploy AccessControlManager
  console.log("\n1. Deploying AccessControlManager...");
  const AccessControlManager = await ethers.getContractFactory("AccessControlManager");
  const accessControl = await AccessControlManager.deploy();
  await accessControl.waitForDeployment();
  console.log("AccessControlManager deployed to:", accessControl.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 2. Deploy TokenManager
  console.log("\n2. Deploying TokenManager...");
  const TokenManager = await ethers.getContractFactory("TokenManager");
  const tokenManager = await TokenManager.deploy(riseTokenAddress, accessControl.target);
  await tokenManager.waitForDeployment();
  console.log("TokenManager deployed to:", tokenManager.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 3. Deploy HorseRegistry
  console.log("\n3. Deploying HorseRegistry...");
  const HorseRegistry = await ethers.getContractFactory("HorseRegistry");
  const horseRegistry = await HorseRegistry.deploy(accessControl.target);
  await horseRegistry.waitForDeployment();
  console.log("HorseRegistry deployed to:", horseRegistry.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 4. Deploy PowerUpSystem
  console.log("\n4. Deploying PowerUpSystem...");
  const PowerUpSystem = await ethers.getContractFactory("PowerUpSystem");
  const powerUpSystem = await PowerUpSystem.deploy(accessControl.target, tokenManager.target);
  await powerUpSystem.waitForDeployment();
  console.log("PowerUpSystem deployed to:", powerUpSystem.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 5. Deploy BettingPool
  console.log("\n5. Deploying BettingPool...");
  const BettingPool = await ethers.getContractFactory("BettingPool");
  const bettingPool = await BettingPool.deploy(accessControl.target, tokenManager.target);
  await bettingPool.waitForDeployment();
  console.log("BettingPool deployed to:", bettingPool.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 6. Deploy RaceEngine
  console.log("\n6. Deploying RaceEngine...");
  const RaceEngine = await ethers.getContractFactory("RaceEngine");
  const raceEngine = await RaceEngine.deploy(accessControl.target, horseRegistry.target, powerUpSystem.target);
  await raceEngine.waitForDeployment();
  console.log("RaceEngine deployed to:", raceEngine.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 7. Deploy RaceManager
  console.log("\n7. Deploying RaceManager...");
  const RaceManager = await ethers.getContractFactory("RaceManager");
  const raceManager = await RaceManager.deploy(
    accessControl.target,
    tokenManager.target,
    horseRegistry.target,
    powerUpSystem.target,
    bettingPool.target,
    raceEngine.target
  );
  await raceManager.waitForDeployment();
  console.log("RaceManager deployed to:", raceManager.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 8. Deploy RaceScheduler
  console.log("\n8. Deploying RaceScheduler...");
  const RaceScheduler = await ethers.getContractFactory("RaceScheduler");
  const raceScheduler = await RaceScheduler.deploy(accessControl.target, raceManager.target);
  await raceScheduler.waitForDeployment();
  console.log("RaceScheduler deployed to:", raceScheduler.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 9. Setup permissions
  console.log("\n9. Setting up permissions...");
  
  // Grant RaceManager role to both contracts
  await accessControl.grantRaceManagerRole(raceManager.target);
  console.log("Granted RaceManager role to:", raceManager.target);

  console.log("Waiting 2 seconds...");
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  await accessControl.grantRaceManagerRole(raceScheduler.target);
  console.log("Granted RaceManager role to:", raceScheduler.target);

  // Summary
  console.log("\n=== DEPLOYMENT SUMMARY ===");
  console.log("Network: Rise Chain Testnet");
  console.log("Chain ID: 11155931");
  console.log("RISE Token:", riseTokenAddress);
  console.log("\nContract Addresses:");
  console.log("AccessControlManager:", accessControl.target);
  console.log("TokenManager:", tokenManager.target);
  console.log("HorseRegistry:", horseRegistry.target);
  console.log("PowerUpSystem:", powerUpSystem.target);
  console.log("BettingPool:", bettingPool.target);
  console.log("RaceEngine:", raceEngine.target);
  console.log("RaceManager:", raceManager.target);
  console.log("RaceScheduler:", raceScheduler.target);
  
  console.log("\n=== NEXT STEPS ===");
  console.log("1. Get RISE tokens from faucet: https://faucet.testnet.riselabs.xyz");
  console.log("2. Approve RISE tokens for contracts");
  console.log("3. Create your first race using RaceManager.createRace()");
  console.log("4. Test betting and power-up features");
  console.log("5. Use RaceScheduler for automated races");
  
  // Save deployment addresses to file
  const fs = require('fs');
  const deploymentAddresses = {
    network: "riseTestnet",
    chainId: 11155931,
    riseToken: riseTokenAddress,
    contracts: {
      accessControl: accessControl.target,
      tokenManager: tokenManager.target,
      horseRegistry: horseRegistry.target,
      powerUpSystem: powerUpSystem.target,
      bettingPool: bettingPool.target,
      raceEngine: raceEngine.target,
      raceManager: raceManager.target,
      raceScheduler: raceScheduler.target
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