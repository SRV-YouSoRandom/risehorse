// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./AccessControl.sol";
import "./RaceManager.sol";

contract RaceScheduler {
    AccessControlManager public immutable accessControl;
    RaceManager public immutable raceManager;
    
    enum ScheduleType { NONE, DAILY, WEEKLY, CUSTOM_INTERVAL }
    
    struct RaceSchedule {
        uint256 scheduleId;
        string baseName;
        uint256[] participatingHorses;
        uint256 bettingDuration;
        ScheduleType scheduleType;
        uint256 interval;
        uint256 nextRaceTime;
        bool isActive;
        uint256 maxRaces;
        uint256 racesCreated;
        address creator;
        uint256 createdAt;
    }
    
    mapping(uint256 => RaceSchedule) public raceSchedules;
    uint256 public totalSchedules;
    
    // Queue for scheduled races ready to be created
    uint256[] public pendingScheduledRaces;
    mapping(uint256 => bool) public isPendingSchedule;
    
    event RaceScheduleCreated(uint256 indexed scheduleId, string baseName, ScheduleType scheduleType, uint256 interval);
    event ScheduledRaceGenerated(uint256 indexed scheduleId, uint256 indexed raceId, uint256 nextScheduledTime);
    event RaceScheduleUpdated(uint256 indexed scheduleId, bool isActive);

    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "RaceScheduler: Only admin");
        _;
    }

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isOperator(msg.sender),
            "RaceScheduler: Not authorized"
        );
        _;
    }

    constructor(address _accessControl, address _raceManager) {
        accessControl = AccessControlManager(_accessControl);
        raceManager = RaceManager(_raceManager);
    }

    function createRaceSchedule(
        string memory baseName,
        uint256[] memory participatingHorses,
        uint256 bettingDuration,
        ScheduleType scheduleType,
        uint256 interval,
        uint256 firstRaceTime,
        uint256 maxRaces
    ) external onlyAdmin returns (uint256) {
        require(participatingHorses.length >= 2 && participatingHorses.length <= 10, "RaceScheduler: Invalid horse count");
        require(bettingDuration >= 300 && bettingDuration <= 3600, "RaceScheduler: Invalid betting duration");
        require(scheduleType != ScheduleType.NONE, "RaceScheduler: Invalid schedule type");
        require(firstRaceTime > block.timestamp, "RaceScheduler: First race must be in future");
        
        if (scheduleType == ScheduleType.DAILY) {
            interval = 86400; // 24 hours
        } else if (scheduleType == ScheduleType.WEEKLY) {
            interval = 604800; // 7 days
        } else if (scheduleType == ScheduleType.CUSTOM_INTERVAL) {
            require(interval >= 3600, "RaceScheduler: Minimum 1 hour interval");
        }
        
        totalSchedules++;
        uint256 scheduleId = totalSchedules;
        
        raceSchedules[scheduleId] = RaceSchedule({
            scheduleId: scheduleId,
            baseName: baseName,
            participatingHorses: participatingHorses,
            bettingDuration: bettingDuration,
            scheduleType: scheduleType,
            interval: interval,
            nextRaceTime: firstRaceTime,
            isActive: true,
            maxRaces: maxRaces,
            racesCreated: 0,
            creator: msg.sender,
            createdAt: block.timestamp
        });
        
        // Add to pending queue if it's time to create the first race
        if (firstRaceTime <= block.timestamp + 300) { // Within 5 minutes
            _addToPendingQueue(scheduleId);
        }
        
        emit RaceScheduleCreated(scheduleId, baseName, scheduleType, interval);
        return scheduleId;
    }

    function processScheduledRaces() external onlyAuthorized {
        uint256 currentTime = block.timestamp;
        uint256 processed = 0;
        
        // Process up to 5 scheduled races per call to avoid gas limits
        for (uint256 i = 0; i < pendingScheduledRaces.length && processed < 5; i++) {
            uint256 scheduleId = pendingScheduledRaces[i];
            RaceSchedule storage schedule = raceSchedules[scheduleId];
            
            if (!schedule.isActive) {
                _removeFromPendingQueue(i);
                continue;
            }
            
            if (currentTime >= schedule.nextRaceTime) {
                _generateScheduledRace(scheduleId);
                _removeFromPendingQueue(i);
                processed++;
            }
        }
    }

    function checkAndQueueSchedules() external onlyAuthorized {
        uint256 currentTime = block.timestamp;
        uint256 lookAhead = 3600; // 1 hour look ahead
        
        for (uint256 i = 1; i <= totalSchedules; i++) {
            RaceSchedule storage schedule = raceSchedules[i];
            
            if (schedule.isActive && 
                !isPendingSchedule[i] && 
                schedule.nextRaceTime <= currentTime + lookAhead &&
                (schedule.maxRaces == 0 || schedule.racesCreated < schedule.maxRaces)) {
                
                _addToPendingQueue(i);
            }
        }
    }

    function _generateScheduledRace(uint256 scheduleId) internal {
        RaceSchedule storage schedule = raceSchedules[scheduleId];
        
        // Check if we've reached max races
        if (schedule.maxRaces > 0 && schedule.racesCreated >= schedule.maxRaces) {
            schedule.isActive = false;
            return;
        }
        
        // Generate race name with timestamp
        string memory raceName = string(abi.encodePacked(
            schedule.baseName,
            " #",
            _uint2str(schedule.racesCreated + 1)
        ));
        
        // Create the race through RaceManager
        uint256 raceId = raceManager.createRace(
            raceName,
            schedule.participatingHorses,
            schedule.bettingDuration
        );
        
        // Update schedule for next race
        schedule.racesCreated++;
        schedule.nextRaceTime += schedule.interval;
        
        emit ScheduledRaceGenerated(scheduleId, raceId, schedule.nextRaceTime);
        
        // Queue for next race if still active and within limits
        if (schedule.isActive && 
            (schedule.maxRaces == 0 || schedule.racesCreated < schedule.maxRaces)) {
            
            uint256 nextQueueTime = schedule.nextRaceTime - 3600; // Queue 1 hour before
            if (nextQueueTime <= block.timestamp) {
                _addToPendingQueue(scheduleId);
            }
        }
    }

    function _addToPendingQueue(uint256 scheduleId) internal {
        if (!isPendingSchedule[scheduleId]) {
            pendingScheduledRaces.push(scheduleId);
            isPendingSchedule[scheduleId] = true;
        }
    }

    function _removeFromPendingQueue(uint256 index) internal {
        if (index < pendingScheduledRaces.length) {
            uint256 scheduleId = pendingScheduledRaces[index];
            isPendingSchedule[scheduleId] = false;
            
            // Move last element to deleted spot to maintain array
            pendingScheduledRaces[index] = pendingScheduledRaces[pendingScheduledRaces.length - 1];
            pendingScheduledRaces.pop();
        }
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 btmp = bytes1(temp);
            bstr[k] = btmp;
            _i /= 10;
        }
        return string(bstr);
    }

    // Admin functions
    function updateScheduleStatus(uint256 scheduleId, bool isActive) external onlyAdmin {
        require(scheduleId > 0 && scheduleId <= totalSchedules, "RaceScheduler: Invalid schedule ID");
        raceSchedules[scheduleId].isActive = isActive;
        emit RaceScheduleUpdated(scheduleId, isActive);
    }

    function updateScheduleInterval(uint256 scheduleId, uint256 newInterval) external onlyAdmin {
        require(scheduleId > 0 && scheduleId <= totalSchedules, "RaceScheduler: Invalid schedule ID");
        require(newInterval >= 3600, "RaceScheduler: Minimum 1 hour interval");
        raceSchedules[scheduleId].interval = newInterval;
    }

    // View functions
    function getScheduleDetails(uint256 scheduleId) external view returns (
        string memory baseName,
        uint256[] memory participatingHorses,
        uint256 bettingDuration,
        ScheduleType scheduleType,
        uint256 interval,
        uint256 nextRaceTime,
        bool isActive,
        uint256 maxRaces,
        uint256 racesCreated
    ) {
        RaceSchedule memory schedule = raceSchedules[scheduleId];
        return (
            schedule.baseName,
            schedule.participatingHorses,
            schedule.bettingDuration,
            schedule.scheduleType,
            schedule.interval,
            schedule.nextRaceTime,
            schedule.isActive,
            schedule.maxRaces,
            schedule.racesCreated
        );
    }

    function getActiveSchedules() external view returns (uint256[] memory) {
        uint256[] memory activeSchedules = new uint256[](totalSchedules);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= totalSchedules; i++) {
            if (raceSchedules[i].isActive) {
                activeSchedules[count] = i;
                count++;
            }
        }
        
        // Resize array
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeSchedules[i];
        }
        
        return result;
    }

    function getPendingScheduledRaces() external view returns (uint256[] memory) {
        return pendingScheduledRaces;
    }
}