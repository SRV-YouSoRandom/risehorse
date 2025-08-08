// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./AccessControl.sol";
import "./HorseRegistry.sol";
import "./PowerUpSystem.sol";

contract RaceEngine {
    AccessControlManager public immutable accessControl;
    HorseRegistry public immutable horseRegistry;
    PowerUpSystem public immutable powerUpSystem;
    
    enum RaceState { NOT_STARTED, RUNNING, FINISHED }
    
    struct RaceData {
        uint256 raceId;
        uint256[] participatingHorses;
        uint256 startTime;
        uint256 duration;
        mapping(uint256 => uint256) horsePositions; // horseId => position (0-10000 for precision)
        mapping(uint256 => uint256) horseSpeed; // horseId => current speed
        RaceState state;
        uint256 winnerHorseId;
        uint256 lastUpdateTime;
    }
    
    mapping(uint256 => RaceData) public races;
    uint256 public constant RACE_DISTANCE = 10000; // Race distance in position units
    uint256 public constant UPDATE_INTERVAL = 100; // 100ms between updates
    
    event RaceStarted(uint256 indexed raceId, uint256 startTime, uint256[] participatingHorses);
    event HorsePositionUpdate(uint256 indexed raceId, uint256 indexed horseId, uint256 position, uint256 speed);
    event RaceFinished(uint256 indexed raceId, uint256 indexed winnerHorseId, uint256 finishTime);
    event RaceStepSimulated(uint256 indexed raceId, uint256 timestamp);

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isRaceManager(msg.sender),
            "RaceEngine: Not authorized"
        );
        _;
    }

    constructor(address _accessControl, address _horseRegistry, address _powerUpSystem) {
        accessControl = AccessControlManager(_accessControl);
        horseRegistry = HorseRegistry(_horseRegistry);
        powerUpSystem = PowerUpSystem(_powerUpSystem);
    }

    function initializeRace(uint256 raceId, uint256[] memory participatingHorses) external onlyAuthorized {
        require(races[raceId].state == RaceState.NOT_STARTED, "RaceEngine: Race already initialized");
        require(participatingHorses.length >= 2 && participatingHorses.length <= 10, "RaceEngine: Invalid number of horses");
        
        RaceData storage race = races[raceId];
        race.raceId = raceId;
        race.participatingHorses = participatingHorses;
        race.duration = 30 + (participatingHorses.length * 5); // 30-80 seconds based on horse count
        
        // Initialize horse positions and speeds
        for (uint256 i = 0; i < participatingHorses.length; i++) {
            uint256 horseId = participatingHorses[i];
            race.horsePositions[horseId] = 0;
            race.horseSpeed[horseId] = horseRegistry.calculateBaseSpeed(horseId);
        }
    }

    function startRaceSimulation(uint256 raceId) external onlyAuthorized {
        require(races[raceId].state == RaceState.NOT_STARTED, "RaceEngine: Race already started");
        
        races[raceId].state = RaceState.RUNNING;
        races[raceId].startTime = block.timestamp;
        races[raceId].lastUpdateTime = block.timestamp;
        
        emit RaceStarted(raceId, block.timestamp, races[raceId].participatingHorses);
    }

    function simulateRaceStep(uint256 raceId) external onlyAuthorized {
        RaceData storage race = races[raceId];
        require(race.state == RaceState.RUNNING, "RaceEngine: Race not running");
        require(block.timestamp >= race.lastUpdateTime + (UPDATE_INTERVAL / 1000), "RaceEngine: Too early for update");
        
        bool raceFinished = false;
        uint256 currentTime = block.timestamp;
        
        // Update power-ups for all horses
        for (uint256 i = 0; i < race.participatingHorses.length; i++) {
            uint256 horseId = race.participatingHorses[i];
            powerUpSystem.updateActivePowerUps(raceId, horseId);
        }
        
        // Simulate movement for each horse
        for (uint256 i = 0; i < race.participatingHorses.length; i++) {
            uint256 horseId = race.participatingHorses[i];
            
            if (race.horsePositions[horseId] >= RACE_DISTANCE) {
                continue; // Horse already finished
            }
            
            uint256 baseSpeed = horseRegistry.calculateBaseSpeed(horseId);
            uint256 currentSpeed = powerUpSystem.calculateHorseSpeedWithPowerUps(raceId, horseId, baseSpeed);
            
            // Add some randomness (±20%)
            uint256 randomFactor = _generateRandomness(raceId, horseId, currentTime) % 40;
            currentSpeed = currentSpeed * (80 + randomFactor) / 100;
            
            // Update position
            race.horsePositions[horseId] += currentSpeed;
            race.horseSpeed[horseId] = currentSpeed;
            
            emit HorsePositionUpdate(raceId, horseId, race.horsePositions[horseId], currentSpeed);
            
            // Check if this horse finished first
            if (race.horsePositions[horseId] >= RACE_DISTANCE && race.winnerHorseId == 0) {
                race.winnerHorseId = horseId;
                raceFinished = true;
            }
        }
        
        race.lastUpdateTime = currentTime;
        emit RaceStepSimulated(raceId, currentTime);
        
        if (raceFinished) {
            _finishRace(raceId);
        }
    }

    function _finishRace(uint256 raceId) internal {
        races[raceId].state = RaceState.FINISHED;
        
        // Record race result in horse registry
        for (uint256 i = 0; i < races[raceId].participatingHorses.length; i++) {
            uint256 horseId = races[raceId].participatingHorses[i];
            bool won = (horseId == races[raceId].winnerHorseId);
            horseRegistry.recordRaceResult(horseId, won);
        }
        
        emit RaceFinished(raceId, races[raceId].winnerHorseId, block.timestamp);
    }

    function _generateRandomness(uint256 raceId, uint256 horseId, uint256 timestamp) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(raceId, horseId, timestamp))) % 1000;
    }

    function getRaceState(uint256 raceId) external view returns (RaceState) {
        return races[raceId].state;
    }

    function getHorsePosition(uint256 raceId, uint256 horseId) external view returns (uint256) {
        return races[raceId].horsePositions[horseId];
    }

    function getHorseSpeed(uint256 raceId, uint256 horseId) external view returns (uint256) {
        return races[raceId].horseSpeed[horseId];
    }

    function getRaceWinner(uint256 raceId) external view returns (uint256) {
        require(races[raceId].state == RaceState.FINISHED, "RaceEngine: Race not finished");
        return races[raceId].winnerHorseId;
    }

    function getRaceProgress(uint256 raceId) external view returns (
        uint256[] memory horseIds,
        uint256[] memory positions,
        uint256[] memory speeds
    ) {
        uint256[] memory participatingHorses = races[raceId].participatingHorses;
        uint256 horseCount = participatingHorses.length;
        
        horseIds = new uint256[](horseCount);
        positions = new uint256[](horseCount);
        speeds = new uint256[](horseCount);
        
        for (uint256 i = 0; i < horseCount; i++) {
            uint256 horseId = participatingHorses[i];
            horseIds[i] = horseId;
            positions[i] = races[raceId].horsePositions[horseId];
            speeds[i] = races[raceId].horseSpeed[horseId];
        }
        
        return (horseIds, positions, speeds);
    }

    function isRaceFinished(uint256 raceId) external view returns (bool) {
        return races[raceId].state == RaceState.FINISHED;
    }

    function getParticipatingHorses(uint256 raceId) external view returns (uint256[] memory) {
        return races[raceId].participatingHorses;
    }
}