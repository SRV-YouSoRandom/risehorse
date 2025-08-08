const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Horse Racing Game", function () {
  let accessControl, tokenManager, horseRegistry, powerUpSystem, bettingPool, raceEngine, raceManager;
  let owner, player1, player2;
  let riseToken;

  beforeEach(async function () {
    [owner, player1, player2] = await ethers.getSigners();
    
    // Deploy mock RISE token for testing
    const MockToken = await ethers.getContractFactory("MockERC20");
    riseToken = await MockToken.deploy("RISE Token", "RISE", ethers.utils.parseEther("1000000"));
    
    // Deploy all contracts
    const AccessControlManager = await ethers.getContractFactory("AccessControlManager");
    accessControl = await AccessControlManager.deploy();
    
    const TokenManager = await ethers.getContractFactory("TokenManager");
    tokenManager = await TokenManager.deploy(riseToken.address, accessControl.address);
    
    const HorseRegistry = await ethers.getContractFactory("HorseRegistry");
    horseRegistry = await HorseRegistry.deploy(accessControl.address);
    
    const PowerUpSystem = await ethers.getContractFactory("PowerUpSystem");
    powerUpSystem = await PowerUpSystem.deploy(accessControl.address, tokenManager.address);
    
    const BettingPool = await ethers.getContractFactory("BettingPool");
    bettingPool = await BettingPool.deploy(accessControl.address, tokenManager.address);
    
    const RaceEngine = await ethers.getContractFactory("RaceEngine");
    raceEngine = await RaceEngine.deploy(accessControl.address, horseRegistry.address, powerUpSystem.address);
    
    const RaceManager = await ethers.getContractFactory("RaceManager");
    raceManager = await RaceManager.deploy(
      accessControl.address,
      tokenManager.address,
      horseRegistry.address,
      powerUpSystem.address,
      bettingPool.address,
      raceEngine.address
    );
    
    // Setup permissions
    await accessControl.grantRaceManagerRole(raceManager.address);
    
    // Give players some tokens
    await riseToken.transfer(player1.address, ethers.utils.parseEther("1000"));
    await riseToken.transfer(player2.address, ethers.utils.parseEther("1000"));
  });

  it("Should deploy all contracts correctly", async function () {
    expect(await accessControl.hasRole(await accessControl.ADMIN_ROLE(), owner.address)).to.be.true;
    expect(await horseRegistry.totalHorses()).to.equal(6);
    expect(await tokenManager.riseToken()).to.equal(riseToken.address);
  });

  it("Should create a race", async function () {
    const tx = await raceManager.createRace("Test Race", [1, 2, 3, 4], 300);
    await expect(tx).to.emit(raceManager, "RaceCreated");
    
    const raceDetails = await raceManager.getRaceDetails(1);
    expect(raceDetails[0]).to.equal("Test Race");
    expect(raceDetails[1].length).to.equal(4);
  });

  it("Should allow betting on horses", async function () {
    // Create race
    await raceManager.createRace("Test Race", [1, 2, 3, 4], 300);
    
    // Start betting
    await raceManager.startBettingPhase(1);
    
    // Player1 bets on horse 1
    await riseToken.connect(player1).approve(tokenManager.address, ethers.utils.parseEther("100"));
    await raceManager.connect(player1).placeBet(1, 1, ethers.utils.parseEther("50"));
    
    const userBets = await raceManager.getUserBetsForRace(player1.address, 1);
    expect(userBets.length).to.equal(1);
    expect(userBets[0].amount).to.equal(ethers.utils.parseEther("50"));
  });

  it("Should allow power-up purchases", async function () {
    // Create race and start betting
    await raceManager.createRace("Test Race", [1, 2, 3, 4], 300);
    await raceManager.startBettingPhase(1);
    
    // Player1 buys speed boost for horse 1
    await riseToken.connect(player1).approve(tokenManager.address, ethers.utils.parseEther("100"));
    await raceManager.connect(player1).buyPowerUp(1, 1, 0); // 0 = SPEED_BOOST
    
    const isPowerUpAvailable = await powerUpSystem.isPowerUpAvailable(player1.address, 1, 1);
    expect(isPowerUpAvailable).to.be.false; // Should be false after purchase
  });
});