// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ApprovalLib} from "./ApprovalLib.sol";
import {IFighterRegistry} from "./interfaces/IFighterRegistry.sol";

/// @title Fighter registry
/// @notice One family per World-verified human. K counts every name ever issued and never falls, so deleting a
///         losing bot cannot lower a family's bar. No owner, no setters.
contract FighterRegistry is IFighterRegistry, EIP712 {
    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256("HumanAttestation(address fighter,uint256 nullifier,uint64 expiry)");

    struct Fighter {
        uint256 family;
        address human;
        address moveKey;
        uint256 cap;
        bool isAgent;
        bool unbound;
    }

    address public immutable attester;
    address public immutable registrar;
    uint256 public immutable MAX_STAKE;

    mapping(address => Fighter) private _fighters;
    mapping(uint256 => address) public humanFighter;
    mapping(uint256 => uint256) private _familySize;
    mapping(bytes32 => bool) public approvalUsed;

    constructor(address attester_, address registrar_, uint256 maxStake) {
        if (attester_ == address(0) || registrar_ == address(0) || maxStake == 0) revert ZeroKey();
        attester = attester_;
        registrar = registrar_;
        MAX_STAKE = maxStake;
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return ("NoFlukeFighterRegistry", "1");
    }

    function attestationDigest(address fighter, uint256 nullifier, uint64 expiry) public view returns (bytes32) {
        return _hashTypedData(keccak256(abi.encode(ATTESTATION_TYPEHASH, fighter, nullifier, expiry)));
    }

    function approvalDigest(ApprovalLib.Approval memory a) public view returns (bytes32) {
        return _hashTypedData(ApprovalLib.structHash(a));
    }

    /// @notice Registers the sender as the fighter of a verified human. The backend signs after verifying IDKit.
    function registerHuman(address moveKey, uint256 nullifier, uint64 expiry, bytes calldata sig) external {
        if (block.timestamp > expiry) revert Expired();
        if (moveKey == address(0)) revert ZeroKey();
        if (ECDSA.tryRecover(attestationDigest(msg.sender, nullifier, expiry), sig) != attester) revert BadSignature();
        if (_fighters[msg.sender].family != 0) revert AlreadyRegistered();
        if (nullifier == 0 || humanFighter[nullifier] != address(0)) revert HumanTaken();
        humanFighter[nullifier] = msg.sender;
        _familySize[nullifier] = 1;
        _fighters[msg.sender] = Fighter(nullifier, msg.sender, moveKey, MAX_STAKE, false, false);
        emit HumanRegistered(msg.sender, nullifier, moveKey);
    }

    /// @notice Adds an agent to a human's family, raising K for good. FamilyRegistrar is the only way in.
    function registerAgent(address human, address agent, address moveKey, uint256 maxStake) external {
        if (msg.sender != registrar) revert NotRegistrar();
        Fighter storage h = _fighters[human];
        if (h.family == 0 || h.isAgent) revert NotHuman();
        if (moveKey == address(0) || agent == address(0)) revert ZeroKey();
        if (_fighters[agent].family != 0) revert AlreadyRegistered();
        if (maxStake > MAX_STAKE) revert CapTooHigh();
        uint256 size = ++_familySize[h.family];
        _fighters[agent] = Fighter(h.family, human, moveKey, maxStake, true, false);
        emit AgentRegistered(agent, human, size, maxStake);
        emit AgentCapSet(agent, maxStake);
    }

    /// @notice Retires an agent. Its cap goes to zero and K stays where it is.
    function unbindAgent(address agent) external {
        if (msg.sender != registrar) revert NotRegistrar();
        Fighter storage s = _fighters[agent];
        if (!s.isAgent) revert NotAgent();
        if (s.unbound) revert AgentIsUnbound();
        s.unbound = true;
        s.cap = 0;
        emit AgentUnbound(agent, s.human);
    }

    /// @notice Raises an agent's cap with a fresh World approval. Anyone may submit it.
    function raiseAgentCap(address agent, uint256 maxStake, ApprovalLib.Approval memory a, bytes calldata sig) external {
        Fighter storage s = _fighters[agent];
        if (!s.isAgent) revert NotAgent();
        if (s.unbound) revert AgentIsUnbound();
        bytes32 digest = approvalDigest(a);
        ApprovalLib.check(a, digest, sig, attester, s.human, ApprovalLib.ACTION_RAISE_CAP, keccak256(abi.encode(agent, maxStake)));
        if (approvalUsed[digest]) revert ApprovalLib.ApprovalUsed();
        approvalUsed[digest] = true;
        if (maxStake > MAX_STAKE) revert CapTooHigh();
        s.cap = maxStake;
        emit AgentCapSet(agent, maxStake);
    }

    /// @notice The human can always lower a cap directly, with no signature that could be raced or withheld.
    function lowerAgentCap(address agent, uint256 maxStake) external {
        Fighter storage s = _fighters[agent];
        if (!s.isAgent) revert NotAgent();
        if (msg.sender != s.human) revert NotOwner();
        if (maxStake >= s.cap) revert NotLower();
        s.cap = maxStake;
        emit AgentCapSet(agent, maxStake);
    }

    function setMoveKey(address moveKey) external {
        if (moveKey == address(0)) revert ZeroKey();
        Fighter storage s = _fighters[msg.sender];
        if (s.family == 0) revert NotRegistered();
        s.moveKey = moveKey;
        emit MoveKeySet(msg.sender, moveKey);
    }

    function isRegistered(address fighter) external view returns (bool) {
        return _fighters[fighter].family != 0;
    }

    function moveKeyOf(address fighter) external view returns (address) {
        return _fighters[fighter].moveKey;
    }

    function stakeCapOf(address fighter) external view returns (uint256) {
        return _fighters[fighter].cap;
    }

    function isUnbound(address fighter) external view returns (bool) {
        return _fighters[fighter].unbound;
    }

    function _family(address fighter) private view returns (uint256 f) {
        f = _fighters[fighter].family;
        if (f == 0) revert NotRegistered();
    }

    function humanOf(address fighter) external view returns (address) {
        _family(fighter);
        return _fighters[fighter].human;
    }

    function familyOf(address fighter) external view returns (uint256) {
        return _family(fighter);
    }

    function familySize(address fighter) external view returns (uint256) {
        return _familySize[_family(fighter)];
    }

    function isSameFamily(address a, address b) external view returns (bool) {
        return _family(a) == _family(b);
    }
}
