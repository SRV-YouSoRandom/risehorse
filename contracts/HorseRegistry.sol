// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./AccessControl.sol";

contract HorseRegistry {
    AccessControlManager public immutable accessControl;
    
    struct Horse {
        string name;
        uint256 speed; // Base speed 1-100
        uint256 stamina; // Stamina 1-100
        uint256 consistency; // Consistency 1-100
        bool isActive;
        uint256 totalRaces;
        uint256 wins;
        uint256 created;
    }

    mapping(uint256 => Horse) public horses;
    uint256 public totalHorses;
    
    event HorseRegistered(uint256 indexed horseId, string name, uint256 speed, uint256 stamina, uint256 consistency);
    event HorseStatsUpdated(uint256 indexed horseId, uint256 speed, uint256 stamina, uint256 consistency);
    event HorseRaceCompleted(uint256 indexed horseId, bool won);

    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "HorseRegistry: Only admin");
        _;
    }

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isRaceManager(msg.sender),
            "HorseRegistry: Not authorized"
        );
        _;
    }

    constructor(address _accessControl) {
        accessControl = AccessControlManager(_accessControl);
        _initializeDefaultHorses();
    }

    function _initializeDefaultHorses() internal {
        registerHorse("Risi", 85, 80, 90);
        registerHorse("Ethy", 80, 85, 85);
        registerHorse("Basie", 75, 90, 80);
        registerHorse("Arbi", 90, 75, 85);
        registerHorse("Opie", 85, 85, 75);
        registerHorse("Fuli", 95, 70, 80);
    }

    function registerHorse(string memory name, uint256 speed, uint256 stamina, uint256 consistency) public onlyAdmin {
        require(speed >= 1 && speed <= 100, "HorseRegistry: Invalid speed");
        require(stamina >= 1 && stamina <= 100, "HorseRegistry: Invalid stamina");
        require(consistency >= 1 && consistency <= 100, "HorseRegistry: Invalid consistency");
        
        totalHorses++;
        horses[totalHorses] = Horse({
            name: name,
            speed: speed,
            stamina: stamina,
            consistency: consistency,
            isActive: true,
            totalRaces: 0,
            wins: 0,
            created: block.timestamp
        });
        
        emit HorseRegistered(totalHorses, name, speed, stamina, consistency);
    }

    function updateHorseStats(uint256 horseId, uint256 speed, uint256 stamina, uint256 consistency) external onlyAdmin {
        require(horseId > 0 && horseId <= totalHorses, "HorseRegistry: Invalid horse ID");
        require(speed >= 1 && speed <= 100, "HorseRegistry: Invalid speed");
        require(stamina >= 1 && stamina <= 100, "HorseRegistry: Invalid stamina");
        require(consistency >= 1 && consistency <= 100, "HorseRegistry: Invalid consistency");
        
        horses[horseId].speed = speed;
        horses[horseId].stamina = stamina;
        horses[horseId].consistency = consistency;
        
        emit HorseStatsUpdated(horseId, speed, stamina, consistency);
    }

    function recordRaceResult(uint256 horseId, bool won) external onlyAuthorized {
        require(horseId > 0 && horseId <= totalHorses, "HorseRegistry: Invalid horse ID");
        
        horses[horseId].totalRaces++;
        if (won) {
            horses[horseId].wins++;
        }
        
        emit HorseRaceCompleted(horseId, won);
    }

    function getHorseStats(uint256 horseId) external view returns (Horse memory) {
        require(horseId > 0 && horseId <= totalHorses, "HorseRegistry: Invalid horse ID");
        return horses[horseId];
    }

    function calculateBaseSpeed(uint256 horseId) external view returns (uint256) {
        require(horseId > 0 && horseId <= totalHorses, "HorseRegistry: Invalid horse ID");
        Horse memory horse = horses[horseId];
        
        // Base calculation with some randomness factor
        uint256 baseSpeed = (horse.speed + horse.stamina + horse.consistency) / 3;
        return baseSpeed;
    }

    function getActiveHorses() external view returns (uint256[] memory) {
        uint256[] memory activeHorses = new uint256[](totalHorses);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= totalHorses; i++) {
            if (horses[i].isActive) {
                activeHorses[count] = i;
                count++;
            }
        }
        
        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeHorses[i];
        }
        
        return result;
    }

    function getHorseWinRate(uint256 horseId) external view returns (uint256) {
        require(horseId > 0 && horseId <= totalHorses, "HorseRegistry: Invalid horse ID");
        
        if (horses[horseId].totalRaces == 0) {
            return 0;
        }
        
        return (horses[horseId].wins * 100) / horses[horseId].totalRaces;
    }
}