// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AccessControlManager is AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RACE_MANAGER_ROLE = keccak256("RACE_MANAGER_ROLE");

    event RoleGrantedCustom(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevokedCustom(bytes32 indexed role, address indexed account, address indexed sender);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function grantOperatorRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, account);
        emit RoleGrantedCustom(OPERATOR_ROLE, account, msg.sender);
    }

    function revokeOperatorRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, account);
        emit RoleRevokedCustom(OPERATOR_ROLE, account, msg.sender);
    }

    function grantRaceManagerRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(RACE_MANAGER_ROLE, account);
        emit RoleGrantedCustom(RACE_MANAGER_ROLE, account, msg.sender);
    }

    function isAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    function isOperator(address account) external view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    function isRaceManager(address account) external view returns (bool) {
        return hasRole(RACE_MANAGER_ROLE, account);
    }
}