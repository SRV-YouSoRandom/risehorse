// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./AccessControl.sol";
import "./TokenManager.sol";

contract PowerUpSystem {
    AccessControlManager public immutable accessControl;
    TokenManager public immutable tokenManager;
    
    enum PowerUpType { SPEED_BOOST, STAMINA_RECOVERY }
    
    struct PowerUp {
        PowerUpType powerType;
        uint256 effectStrength; // Percentage boost (1-50)
        uint256 duration; // Duration in seconds
        uint256 cost; // RISE tokens required
        bool isActive;
    }
    
    struct ActivePowerUp {
        PowerUpType powerType;
        uint256 effectStrength;
        uint256 startTime;
        uint256 endTime;
        address purchaser;
        bool isActive;
    }
    
    mapping(PowerUpType => PowerUp) public powerUpTypes;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasPurchasedPowerUp; // raceId => horseId => user => purchased
    mapping(uint256 => mapping(uint256 => ActivePowerUp[])) public racePowerUps; // raceId => horseId => active power-ups
    
    event PowerUpPurchased(uint256 indexed raceId, uint256 indexed horseId, address indexed user, PowerUpType powerType, uint256 cost);
    event PowerUpActivated(uint256 indexed raceId, uint256 indexed horseId, PowerUpType powerType, uint256 duration, address activatedBy);
    event PowerUpExpired(uint256 indexed raceId, uint256 indexed horseId, PowerUpType powerType);

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isRaceManager(msg.sender),
            "PowerUpSystem: Not authorized"
        );
        _;
    }

    constructor(address _accessControl, address _tokenManager) {
        accessControl = AccessControlManager(_accessControl);
        tokenManager = TokenManager(_tokenManager);
        _initializePowerUps();
    }

    function _initializePowerUps() internal {
        // Speed Boost: 50% increase for 5 seconds, costs 10 RISE
        powerUpTypes[PowerUpType.SPEED_BOOST] = PowerUp({
            powerType: PowerUpType.SPEED_BOOST,
            effectStrength: 50,
            duration: 5,
            cost: 10 * 10**18, // 10 RISE tokens
            isActive: true
        });
        
        // Stamina Recovery: 30% sustained speed for 8 seconds, costs 15 RISE
        powerUpTypes[PowerUpType.STAMINA_RECOVERY] = PowerUp({
            powerType: PowerUpType.STAMINA_RECOVERY,
            effectStrength: 30,
            duration: 8,
            cost: 15 * 10**18, // 15 RISE tokens
            isActive: true
        });
    }

    function buyPowerUp(uint256 raceId, uint256 horseId, PowerUpType powerType) external {
        require(!hasPurchasedPowerUp[raceId][horseId][msg.sender], "PowerUpSystem: Already purchased power-up for this horse");
        require(powerUpTypes[powerType].isActive, "PowerUpSystem: Power-up type not available");
        
        uint256 cost = powerUpTypes[powerType].cost;
        require(tokenManager.getUserBalance(msg.sender) >= cost, "PowerUpSystem: Insufficient RISE tokens");
        require(tokenManager.getUserAllowance(msg.sender) >= cost, "PowerUpSystem: Insufficient allowance");
        
        // Transfer tokens
        require(tokenManager.transferTokensForPowerUp(msg.sender, cost), "PowerUpSystem: Token transfer failed");
        
        // Mark as purchased
        hasPurchasedPowerUp[raceId][horseId][msg.sender] = true;
        
        emit PowerUpPurchased(raceId, horseId, msg.sender, powerType, cost);
    }

    function activatePowerUp(uint256 raceId, uint256 horseId, PowerUpType powerType, address user) external onlyAuthorized {
        require(hasPurchasedPowerUp[raceId][horseId][user], "PowerUpSystem: Power-up not purchased");
        
        PowerUp memory powerUp = powerUpTypes[powerType];
        
        // Check if horse already has this power-up type active
        ActivePowerUp[] storage activePowerUps = racePowerUps[raceId][horseId];
        for (uint256 i = 0; i < activePowerUps.length; i++) {
            if (activePowerUps[i].isActive && activePowerUps[i].powerType == powerType) {
                revert("PowerUpSystem: Power-up type already active");
            }
        }
        
        // Add new active power-up
        activePowerUps.push(ActivePowerUp({
            powerType: powerType,
            effectStrength: powerUp.effectStrength,
            startTime: block.timestamp,
            endTime: block.timestamp + powerUp.duration,
            purchaser: user,
            isActive: true
        }));
        
        emit PowerUpActivated(raceId, horseId, powerType, powerUp.duration, user);
    }

    function updateActivePowerUps(uint256 raceId, uint256 horseId) external onlyAuthorized {
        ActivePowerUp[] storage activePowerUps = racePowerUps[raceId][horseId];
        
        for (uint256 i = 0; i < activePowerUps.length; i++) {
            if (activePowerUps[i].isActive && block.timestamp > activePowerUps[i].endTime) {
                activePowerUps[i].isActive = false;
                emit PowerUpExpired(raceId, horseId, activePowerUps[i].powerType);
            }
        }
    }

    function getActivePowerUps(uint256 raceId, uint256 horseId) external view returns (ActivePowerUp[] memory) {
        ActivePowerUp[] memory allPowerUps = racePowerUps[raceId][horseId];
        uint256 activeCount = 0;
        
        // Count active power-ups
        for (uint256 i = 0; i < allPowerUps.length; i++) {
            if (allPowerUps[i].isActive && block.timestamp <= allPowerUps[i].endTime) {
                activeCount++;
            }
        }
        
        // Create array of active power-ups
        ActivePowerUp[] memory activePowerUps = new ActivePowerUp[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allPowerUps.length; i++) {
            if (allPowerUps[i].isActive && block.timestamp <= allPowerUps[i].endTime) {
                activePowerUps[index] = allPowerUps[i];
                index++;
            }
        }
        
        return activePowerUps;
    }

    function isPowerUpAvailable(address user, uint256 raceId, uint256 horseId) external view returns (bool) {
        return !hasPurchasedPowerUp[raceId][horseId][user];
    }

    function getPowerUpCost(PowerUpType powerType) external view returns (uint256) {
        return powerUpTypes[powerType].cost;
    }

    function calculateHorseSpeedWithPowerUps(uint256 raceId, uint256 horseId, uint256 baseSpeed) external view returns (uint256) {
        ActivePowerUp[] memory activePowerUps = this.getActivePowerUps(raceId, horseId);
        uint256 modifiedSpeed = baseSpeed;
        
        for (uint256 i = 0; i < activePowerUps.length; i++) {
            if (activePowerUps[i].powerType == PowerUpType.SPEED_BOOST) {
                modifiedSpeed = modifiedSpeed * (100 + activePowerUps[i].effectStrength) / 100;
            } else if (activePowerUps[i].powerType == PowerUpType.STAMINA_RECOVERY) {
                modifiedSpeed = modifiedSpeed * (100 + activePowerUps[i].effectStrength) / 100;
            }
        }
        
        return modifiedSpeed;
    }
}