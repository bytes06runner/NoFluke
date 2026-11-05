// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFighterRegistry {
    event HumanRegistered(address indexed fighter, uint256 indexed nullifier, address moveKey);
    event AgentRegistered(address indexed agent, address indexed human, uint256 familySize, uint256 maxStake);
    event AgentUnbound(address indexed agent, address indexed human);
    event AgentCapSet(address indexed agent, uint256 maxStake);
    event MoveKeySet(address indexed fighter, address moveKey);

    error AlreadyRegistered();
    error HumanTaken();
    error NotRegistered();
    error NotHuman();
    error NotRegistrar();
    error NotAgent();
    error NotOwner();
    error NotLower();
    error CapTooHigh();
    error AgentIsUnbound();
    error BadSignature();
    error Expired();
    error ZeroKey();

    function isRegistered(address fighter) external view returns (bool);
    function moveKeyOf(address fighter) external view returns (address);
    function stakeCapOf(address fighter) external view returns (uint256);
    function humanOf(address fighter) external view returns (address);
    function familyOf(address fighter) external view returns (uint256);
    function familySize(address fighter) external view returns (uint256);
    function isSameFamily(address a, address b) external view returns (bool);
    function isUnbound(address fighter) external view returns (bool);
    function registerAgent(address human, address agent, address moveKey, uint256 maxStake) external;
    function unbindAgent(address agent) external;
}
