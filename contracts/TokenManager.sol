// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AccessControl.sol";

contract TokenManager is ReentrancyGuard {
    IERC20 public immutable riseToken;
    AccessControlManager public immutable accessControl;
    
    uint256 public constant HOUSE_FEE_PERCENTAGE = 5; // 5%
    uint256 public totalFeesCollected;
    
    event TokensTransferred(address indexed from, address indexed to, uint256 amount, string purpose);
    event FeesCollected(uint256 amount);
    event PayoutDistributed(address indexed user, uint256 amount);

    modifier onlyAuthorized() {
        require(
            accessControl.isAdmin(msg.sender) || 
            accessControl.isOperator(msg.sender) || 
            accessControl.isRaceManager(msg.sender),
            "TokenManager: Not authorized"
        );
        _;
    }

    constructor(address _riseToken, address _accessControl) {
        riseToken = IERC20(_riseToken);
        accessControl = AccessControlManager(_accessControl);
    }

    function transferTokensForBet(address user, uint256 amount) external onlyAuthorized nonReentrant returns (bool) {
        require(riseToken.transferFrom(user, address(this), amount), "TokenManager: Bet transfer failed");
        emit TokensTransferred(user, address(this), amount, "BET");
        return true;
    }

    function transferTokensForPowerUp(address user, uint256 amount) external onlyAuthorized nonReentrant returns (bool) {
        require(riseToken.transferFrom(user, address(this), amount), "TokenManager: PowerUp transfer failed");
        emit TokensTransferred(user, address(this), amount, "POWERUP");
        return true;
    }

    function distributePayout(address user, uint256 amount) external onlyAuthorized nonReentrant returns (bool) {
        require(riseToken.transfer(user, amount), "TokenManager: Payout transfer failed");
        emit PayoutDistributed(user, amount);
        return true;
    }

    function collectFees(uint256 amount) external onlyAuthorized {
        uint256 feeAmount = (amount * HOUSE_FEE_PERCENTAGE) / 100;
        totalFeesCollected += feeAmount;
        emit FeesCollected(feeAmount);
    }

    function withdrawFees() external {
        require(accessControl.isAdmin(msg.sender), "TokenManager: Only admin can withdraw fees");
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;
        require(riseToken.transfer(msg.sender, amount), "TokenManager: Fee withdrawal failed");
    }

    function getUserBalance(address user) external view returns (uint256) {
        return riseToken.balanceOf(user);
    }

    function getUserAllowance(address user) external view returns (uint256) {
        return riseToken.allowance(user, address(this));
    }

    function getContractBalance() external view returns (uint256) {
        return riseToken.balanceOf(address(this));
    }
}