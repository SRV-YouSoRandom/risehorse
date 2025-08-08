// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./TokenManager.sol";
import "./HorseRegistry.sol";
import "./PowerUpSystem.sol";
import "./BettingPool.sol";
import "./RaceEngine.sol";

contract RaceManager is ReentrancyGuard {
    AccessControlManager public immutable accessControl;
    TokenManager public immutable tokenManager;
    HorseRegistry public immutable horseRegistry;
    PowerUpSystem public immutable powerUpSystem;
    BettingPool public immutable bettingPool;
    RaceEngine public immutable raceEngine;
    
    enum RacePhase { CREATED, BETTING_OPEN, BETTING_CLOSED, RACING, FINISHED }
    
    struct Race {
        uint256 raceId;
        string name;
        uint256[] participatingHorses;
        uint256 bettingStartTime;
        uint256 bettingEndTime;
        uint256 raceStartTime;
        RacePhase phase;
        uint256 createdAt;
        address creator;
    }
    
    mapping(uint256 => Race) public races;
    uint256 public totalRaces;
    uint256 public activeRaceId;
    
    event RaceCreated(uint256 indexed raceId, string name, uint256[] participatingHorses, uint256 bettingStartTime);
    event BettingPhaseStarted(uint256 indexed raceId, uint256 startTime, uint256 endTime);
    event BettingPhaseClosed(uint256 indexed raceId);
    event RacePhaseStarted(uint256 indexed raceId, uint256 startTime);
    event RaceCompleted(uint256 indexed raceId, uint256 winnerHorseId, uint256 completionTime);

    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "RaceManager: Only admin");
        _;
    }

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isOperator(msg.sender),
            "RaceManager: Not authorized"
        );
        _;
    }

    constructor(
        address _accessControl,
        address _tokenManager,
        address _horseRegistry,
        address _powerUpSystem,
        address _bettingPool,
        address _raceEngine
    ) {
        accessControl = AccessControlManager(_accessControl);
        tokenManager = TokenManager(_tokenManager);
        horseRegistry = HorseRegistry(_horseRegistry);
        powerUpSystem = PowerUpSystem(_powerUpSystem);
        bettingPool = BettingPool(_bettingPool);
        raceEngine = RaceEngine(_raceEngine);
    }

    function createRace(
        string memory name,
        uint256[] memory participatingHorses,
        uint256 bettingDuration
    ) external onlyAdmin returns (uint256) {
        require(participatingHorses.length >= 2 && participatingHorses.length <= 10, "RaceManager: Invalid horse count");
        require(bettingDuration >= 300 && bettingDuration <= 3600, "RaceManager: Invalid betting duration"); // 5min to 1hour
        
        totalRaces++;
        uint256 raceId = totalRaces;
        
        uint256 bettingStart = block.timestamp + 60; // Start betting in 1 minute
        uint256 bettingEnd = bettingStart + bettingDuration;
        
        races[raceId] = Race({
            raceId: raceId,
            name: name,
            participatingHorses: participatingHorses,
            bettingStartTime: bettingStart,
            bettingEndTime: bettingEnd,
            raceStartTime: bettingEnd + 30, // Race starts 30 seconds after betting ends
            phase: RacePhase.CREATED,
            createdAt: block.timestamp,
            creator: msg.sender
        });
        
        // Initialize race in engine
        raceEngine.initializeRace(raceId, participatingHorses);
        
        emit RaceCreated(raceId, name, participatingHorses, bettingStart);
        return raceId;
    }

    function startBettingPhase(uint256 raceId) external onlyAuthorized {
        require(races[raceId].phase == RacePhase.CREATED, "RaceManager: Invalid race phase");
        require(block.timestamp >= races[raceId].bettingStartTime, "RaceManager: Too early to start betting");
        
        races[raceId].phase = RacePhase.BETTING_OPEN;
        
        emit BettingPhaseStarted(raceId, races[raceId].bettingStartTime, races[raceId].bettingEndTime);
    }

    function closeBettingPhase(uint256 raceId) external onlyAuthorized {
        require(races[raceId].phase == RacePhase.BETTING_OPEN, "RaceManager: Betting not open");
        require(block.timestamp >= races[raceId].bettingEndTime, "RaceManager: Too early to close betting");
        
        races[raceId].phase = RacePhase.BETTING_CLOSED;
        bettingPool.closeBetting(raceId);
        
        emit BettingPhaseClosed(raceId);
    }

    function startRace(uint256 raceId) external onlyAuthorized {
        require(races[raceId].phase == RacePhase.BETTING_CLOSED, "RaceManager: Betting not closed");
        require(block.timestamp >= races[raceId].raceStartTime, "RaceManager: Too early to start race");
        
        races[raceId].phase = RacePhase.RACING;
        activeRaceId = raceId;
        
        raceEngine.startRaceSimulation(raceId);
        
        emit RacePhaseStarted(raceId, block.timestamp);
    }

    function simulateRaceStep(uint256 raceId) external onlyAuthorized {
        require(races[raceId].phase == RacePhase.RACING, "RaceManager: Race not active");
        
        raceEngine.simulateRaceStep(raceId);
        
        // Check if race finished
        if (raceEngine.isRaceFinished(raceId)) {
            _completeRace(raceId);
        }
    }

    function _completeRace(uint256 raceId) internal {
        races[raceId].phase = RacePhase.FINISHED;
        
        uint256 winnerHorseId = raceEngine.getRaceWinner(raceId);
        bettingPool.distributePayout(raceId, winnerHorseId);
        
        if (activeRaceId == raceId) {
            activeRaceId = 0;
        }
        
        emit RaceCompleted(raceId, winnerHorseId, block.timestamp);
    }

    function placeBet(uint256 raceId, uint256 horseId, uint256 amount) external {
        require(races[raceId].phase == RacePhase.BETTING_OPEN, "RaceManager: Betting not open");
        require(block.timestamp <= races[raceId].bettingEndTime, "RaceManager: Betting period ended");
        
        // Verify horse is participating
        bool horseParticipating = false;
        for (uint256 i = 0; i < races[raceId].participatingHorses.length; i++) {
            if (races[raceId].participatingHorses[i] == horseId) {
                horseParticipating = true;
                break;
            }
        }
        require(horseParticipating, "RaceManager: Horse not participating");
        
        bettingPool.placeBet(raceId, horseId, amount);
    }

    function buyPowerUp(uint256 raceId, uint256 horseId, PowerUpSystem.PowerUpType powerType) external {
        require(races[raceId].phase == RacePhase.BETTING_OPEN || races[raceId].phase == RacePhase.BETTING_CLOSED, 
                "RaceManager: Invalid phase for power-up purchase");
        
        // Verify horse is participating
        bool horseParticipating = false;
        for (uint256 i = 0; i < races[raceId].participatingHorses.length; i++) {
            if (races[raceId].participatingHorses[i] == horseId) {
                horseParticipating = true;
                break;
            }
        }
        require(horseParticipating, "RaceManager: Horse not participating");
        
        powerUpSystem.buyPowerUp(raceId, horseId, powerType);
    }

    function activatePowerUp(uint256 raceId, uint256 horseId, PowerUpSystem.PowerUpType powerType) external {
        require(races[raceId].phase == RacePhase.RACING, "RaceManager: Race not active");
        
        powerUpSystem.activatePowerUp(raceId, horseId, powerType, msg.sender);
    }

    function getRaceDetails(uint256 raceId) external view returns (
        string memory name,
        uint256[] memory participatingHorses,
        uint256 bettingStartTime,
        uint256 bettingEndTime,
        uint256 raceStartTime,
        RacePhase phase,
        uint256 totalPool
    ) {
        Race memory race = races[raceId];
        uint256 pool = bettingPool.getTotalPool(raceId);
        
        return (
            race.name,
            race.participatingHorses,
            race.bettingStartTime,
            race.bettingEndTime,
            race.raceStartTime,
            race.phase,
            pool
        );
    }

    function getCurrentRaceState(uint256 raceId) external view returns (
        RacePhase phase,
        uint256 timeRemaining,
        bool canBet,
        bool canBuyPowerUps,
        bool isRacing
    ) {
        Race memory race = races[raceId];
        uint256 currentTime = block.timestamp;
        
        uint256 timeLeft = 0;
        if (race.phase == RacePhase.BETTING_OPEN && currentTime < race.bettingEndTime) {
            timeLeft = race.bettingEndTime - currentTime;
        } else if (race.phase == RacePhase.BETTING_CLOSED && currentTime < race.raceStartTime) {
            timeLeft = race.raceStartTime - currentTime;
        }
        
        return (
            race.phase,
            timeLeft,
            race.phase == RacePhase.BETTING_OPEN && currentTime <= race.bettingEndTime,
            race.phase == RacePhase.BETTING_OPEN || race.phase == RacePhase.BETTING_CLOSED,
            race.phase == RacePhase.RACING
        );
    }

    function getActiveRace() external view returns (uint256) {
        return activeRaceId;
    }

    function getUserBetsForRace(address user, uint256 raceId) external view returns (BettingPool.Bet[] memory) {
        return bettingPool.getUserBets(user, raceId);
    }

    function getHorseOdds(uint256 raceId, uint256 horseId) external view returns (uint256) {
        return bettingPool.calculateOdds(raceId, horseId);
    }

    function withdrawWinnings() external {
        bettingPool.withdrawWinnings();
    }

    function getPendingWinnings(address user) external view returns (uint256) {
        return bettingPool.getPendingWithdrawals(user);
    }

    function emergencyPause() external onlyAdmin {
        accessControl.pause();
    }

    function emergencyUnpause() external onlyAdmin {
        accessControl.unpause();
    }
}