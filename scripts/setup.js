const hre = require("hardhat");
const deployments = require("../deployments.json");

async function main() {
  console.log("Setting up Horse Racing Game...");
  
  const [deployer] = await hre.ethers.getSigners();
  console.log("Setup account:", deployer.address);

  // Get contract instances
  const raceManager = await hre.ethers.getContractAt("RaceManager", deployments.contracts.raceManager);
  const tokenManager = await hre.ethers.getContractAt("TokenManager", deployments.contracts.tokenManager);
  const horseRegistry = await hre.ethers.getContractAt("HorseRegistry", deployments.contracts.horseRegistry);
  
  // Check horses
  console.log("\n=== CHECKING HORSES ===");
  const totalHorses = await horseRegistry.totalHorses();
  console.log("Total horses registered:", totalHorses.toString());
  
  for (let i = 1; i <= totalHorses; i++) {
    const horse = await horseRegistry.getHorseStats(i);
    console.log(`Horse ${i}: ${horse.name} (Speed: ${horse.speed}, Stamina: ${horse.stamina}, Consistency: ${horse.consistency})`);
  }
  
  // Create a demo race
  console.log("\n=== CREATING DEMO RACE ===");
  const participatingHorses = [1, 2, 3, 4, 5, 6]; // All horses
  const bettingDuration = 600; // 10 minutes
  
  try {
    const tx = await raceManager.createRace("Demo Race - Rise Chain", participatingHorses, bettingDuration);
    const receipt = await tx.wait();
    console.log("Demo race created! Transaction hash:", receipt.transactionHash);
    
    // Get race details
    const raceDetails = await raceManager.getRaceDetails(1);
    console.log("Race Name:", raceDetails[0]);
    console.log("Participating Horses:", raceDetails[1].map(h => h.toString()));
    console.log("Betting Start Time:", new Date(raceDetails[2].toNumber() * 1000));
    console.log("Betting End Time:", new Date(raceDetails[3].toNumber() * 1000));
    console.log("Race Start Time:", new Date(raceDetails[4].toNumber() * 1000));
    
  } catch (error) {
    console.log("Race creation failed (maybe already exists):", error.message);
  }
  
  console.log("\n=== SETUP COMPLETE ===");
  console.log("Frontend can now connect to:", deployments.contracts.raceManager);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });