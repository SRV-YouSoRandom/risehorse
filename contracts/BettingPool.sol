// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./TokenManager.sol";

contract BettingPool is ReentrancyGuard {
    AccessControlManager public immutable accessControl;
    TokenManager public immutable tokenManager;
    
    struct Bet {
        address bettor;
        uint256 horseId;
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }
    
    struct RaceBettingInfo {
        uint256 totalPool;
        mapping(uint256 => uint256) horsePool; // horseId => total bet amount
        mapping(address => Bet[]) userBets;
        mapping(uint256 => address[]) horseBettors; // horseId => list of bettors
        bool bettingClosed;
        bool payoutsDistributed;
        uint256 winningHorseId;
    }
    
    mapping(uint256 => RaceBettingInfo) public raceBets;
    mapping(address => uint256) public pendingWithdrawals;
    
    uint256 public constant MIN_BET = 1 * 10**18; // 1 RISE
    uint256 public constant MAX_BET = 1000 * 10**18; // 1000 RISE
    
    event BetPlaced(uint256 indexed raceId, address indexed bettor, uint256 indexed horseId, uint256 amount);
    event BettingClosed(uint256 indexed raceId, uint256 totalPool);
    event PayoutCalculated(uint256 indexed raceId, uint256 indexed horseId, uint256 totalPayout, uint256 numWinners);
    event WinningsWithdrawn(address indexed user, uint256 amount);

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isRaceManager(msg.sender),
            "BettingPool: Not authorized"
        );
        _;
    }

    constructor(address _accessControl, address _tokenManager) {
        accessControl = AccessControlManager(_accessControl);
        tokenManager = TokenManager(_tokenManager);
    }

    function placeBet(uint256 raceId, uint256 horseId, uint256 amount) external nonReentrant {
        require(amount >= MIN_BET && amount <= MAX_BET, "BettingPool: Invalid bet amount");
        require(!raceBets[raceId].bettingClosed, "BettingPool: Betting is closed");
        require(tokenManager.getUserBalance(msg.sender) >= amount, "BettingPool: Insufficient balance");
        require(tokenManager.getUserAllowance(msg.sender) >= amount, "BettingPool: Insufficient allowance");
        
        // Transfer tokens to contract
        require(tokenManager.transferTokensForBet(msg.sender, amount), "BettingPool: Token transfer failed");
        
        // Record bet
        raceBets[raceId].userBets[msg.sender].push(Bet({
            bettor: msg.sender,
            horseId: horseId,
            amount: amount,
            timestamp: block.timestamp,
            claimed: false
        }));
        
        // Update pools
        raceBets[raceId].totalPool += amount;
        raceBets[raceId].horsePool[horseId] += amount;
        raceBets[raceId].horseBettors[horseId].push(msg.sender);
        
        emit BetPlaced(raceId, msg.sender, horseId, amount);
    }

    function closeBetting(uint256 raceId) external onlyAuthorized {
        require(!raceBets[raceId].bettingClosed, "BettingPool: Betting already closed");
        
        raceBets[raceId].bettingClosed = true;
        emit BettingClosed(raceId, raceBets[raceId].totalPool);
    }

    function distributePayout(uint256 raceId, uint256 winningHorseId) external onlyAuthorized nonReentrant {
        require(raceBets[raceId].bettingClosed, "BettingPool: Betting not closed");
        require(!raceBets[raceId].payoutsDistributed, "BettingPool: Payouts already distributed");
        
        raceBets[raceId].winningHorseId = winningHorseId;
        raceBets[raceId].payoutsDistributed = true;
        
        uint256 totalPool = raceBets[raceId].totalPool;
        uint256 winningPool = raceBets[raceId].horsePool[winningHorseId];
        
        if (winningPool == 0) {
            // No winners, house keeps all
            tokenManager.collectFees(totalPool);
            return;
        }
        
        // Calculate house fee (5%)
        uint256 houseShare = (totalPool * 5) / 100;
        uint256 payoutPool = totalPool - houseShare;
        
        tokenManager.collectFees(houseShare);
        
        // Calculate individual payouts
        address[] memory winners = raceBets[raceId].horseBettors[winningHorseId];
        uint256 totalWinners = 0;
        
        // Count unique winners
        for (uint256 i = 0; i < winners.length; i++) {
            bool alreadyCounted = false;
            for (uint256 j = 0; j < i; j++) {
                if (winners[i] == winners[j]) {
                    alreadyCounted = true;
                    break;
                }
            }
            if (!alreadyCounted) {
                totalWinners++;
            }
        }
        
        // Distribute payouts to each winner based on their bet proportion
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            
            // Calculate total bet by this winner on winning horse
            uint256 winnerBetTotal = 0;
            Bet[] storage userBets = raceBets[raceId].userBets[winner];
            
            for (uint256 j = 0; j < userBets.length; j++) {
                if (userBets[j].horseId == winningHorseId && !userBets[j].claimed) {
                    winnerBetTotal += userBets[j].amount;
                    userBets[j].claimed = true;
                }
            }
            
            if (winnerBetTotal > 0) {
                uint256 payout = (payoutPool * winnerBetTotal) / winningPool;
                pendingWithdrawals[winner] += payout;
            }
        }
        
        emit PayoutCalculated(raceId, winningHorseId, payoutPool, totalWinners);
    }

    function withdrawWinnings() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "BettingPool: No winnings to withdraw");
        
        pendingWithdrawals[msg.sender] = 0;
        require(tokenManager.distributePayout(msg.sender, amount), "BettingPool: Withdrawal failed");
        
        emit WinningsWithdrawn(msg.sender, amount);
    }

    function calculateOdds(uint256 raceId, uint256 horseId) external view returns (uint256) {
        uint256 totalPool = raceBets[raceId].totalPool;
        uint256 horsePool = raceBets[raceId].horsePool[horseId];
        
        if (horsePool == 0 || totalPool == 0) {
            return 0;
        }
        
        // Return odds as percentage (e.g., 300 = 3.00x)
        return (totalPool * 100) / horsePool;
    }

    function getUserBets(address user, uint256 raceId) external view returns (Bet[] memory) {
        return raceBets[raceId].userBets[user];
    }

    function getTotalPool(uint256 raceId) external view returns (uint256) {
        return raceBets[raceId].totalPool;
    }

    function getHorsePool(uint256 raceId, uint256 horseId) external view returns (uint256) {
        return raceBets[raceId].horsePool[horseId];
    }

    function getRaceBettingInfo(uint256 raceId) external view returns (
        uint256 totalPool,
        bool bettingClosed,
        bool payoutsDistributed,
        uint256 winningHorseId
    ) {
        RaceBettingInfo storage raceInfo = raceBets[raceId];
        return (
            raceInfo.totalPool,
            raceInfo.bettingClosed,
            raceInfo.payoutsDistributed,
            raceInfo.winningHorseId
        );
    }

    function getPendingWithdrawals(address user) external view returns (uint256) {
        return pendingWithdrawals[user];
    }
}