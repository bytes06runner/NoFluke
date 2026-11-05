// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FighterRegistry} from "../src/FighterRegistry.sol";
import {IFighterRegistry} from "../src/interfaces/IFighterRegistry.sol";
import {ApprovalLib} from "../src/ApprovalLib.sol";

contract FighterRegistryTest is Test {
    FighterRegistry reg;
    uint256 attesterKey = 0xA77E;
    address attester;
    address registrar = address(0xEEEE);
    address human = address(0x1);
    address agent = address(0x2);
    address moveKey = address(0x3);
    uint256 nullifier = 12345;

    function setUp() public {
        attester = vm.addr(attesterKey);
        reg = new FighterRegistry(attester, registrar, 10_000_000);
        vm.warp(1_800_000_000);
    }

    function _attest(address fighter, uint256 n, uint64 expiry, uint256 key) internal view returns (bytes memory) {
        bytes32 digest = reg.attestationDigest(fighter, n, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _register(address fighter, uint256 n) internal {
        uint64 expiry = uint64(block.timestamp + 60);
        bytes memory sig = _attest(fighter, n, expiry, attesterKey);
        vm.prank(fighter);
        reg.registerHuman(moveKey, n, expiry, sig);
    }

    function _approval(address h, uint8 action, bytes32 paramsHash, uint64 expiry, uint256 nonce)
        internal
        view
        returns (ApprovalLib.Approval memory a, bytes memory sig)
    {
        a = ApprovalLib.Approval(h, action, paramsHash, expiry, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, reg.approvalDigest(a));
        sig = abi.encodePacked(r, s, v);
    }

    function test_registerHumanCreatesFamilyOfOne() public {
        _register(human, nullifier);
        assertTrue(reg.isRegistered(human));
        assertEq(reg.familySize(human), 1);
        assertEq(reg.familyOf(human), nullifier);
        assertEq(reg.moveKeyOf(human), moveKey);
        assertEq(reg.stakeCapOf(human), 10_000_000);
    }

    function test_sameNullifierTwiceReverts() public {
        _register(human, nullifier);
        uint64 expiry = uint64(block.timestamp + 60);
        address other = address(0x99);
        bytes memory sig = _attest(other, nullifier, expiry, attesterKey);
        vm.prank(other);
        vm.expectRevert(IFighterRegistry.HumanTaken.selector);
        reg.registerHuman(moveKey, nullifier, expiry, sig);
    }

    function test_attestationRules() public {
        uint64 expiry = uint64(block.timestamp + 60);
        bytes memory wrongSigner = _attest(human, nullifier, expiry, 0xBAD);
        vm.startPrank(human);
        vm.expectRevert(IFighterRegistry.BadSignature.selector);
        reg.registerHuman(moveKey, nullifier, expiry, wrongSigner);
        vm.stopPrank();
        bytes memory forOther = _attest(address(0x7), nullifier, expiry, attesterKey);
        vm.startPrank(human);
        vm.expectRevert(IFighterRegistry.BadSignature.selector);
        reg.registerHuman(moveKey, nullifier, expiry, forOther);
        vm.stopPrank();
        uint64 past = uint64(block.timestamp - 1);
        bytes memory expired = _attest(human, nullifier, past, attesterKey);
        vm.startPrank(human);
        vm.expectRevert(IFighterRegistry.Expired.selector);
        reg.registerHuman(moveKey, nullifier, past, expired);
        bytes memory good = _attest(human, nullifier, expiry, attesterKey);
        vm.expectRevert(IFighterRegistry.ZeroKey.selector);
        reg.registerHuman(address(0), nullifier, expiry, good);
        vm.stopPrank();
    }

    function test_doubleRegistrationReverts() public {
        _register(human, nullifier);
        uint64 expiry = uint64(block.timestamp + 60);
        bytes memory sig = _attest(human, nullifier + 1, expiry, attesterKey);
        vm.prank(human);
        vm.expectRevert(IFighterRegistry.AlreadyRegistered.selector);
        reg.registerHuman(moveKey, nullifier + 1, expiry, sig);
    }

    function test_onlyRegistrarCanAddAgents() public {
        _register(human, nullifier);
        vm.expectRevert(IFighterRegistry.NotRegistrar.selector);
        reg.registerAgent(human, agent, moveKey, 1e6);
    }

    function test_agentGrowsFamilyAndCap() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        assertEq(reg.familySize(human), 2);
        assertEq(reg.familySize(agent), 2);
        assertEq(reg.stakeCapOf(agent), 1e6);
        assertEq(reg.humanOf(agent), human);
        assertTrue(reg.isSameFamily(human, agent));
    }

    function test_agentMustBelongToARegisteredHuman() public {
        vm.prank(registrar);
        vm.expectRevert(IFighterRegistry.NotHuman.selector);
        reg.registerAgent(human, agent, moveKey, 1e6);
    }

    function test_agentCannotOwnAgents() public {
        _register(human, nullifier);
        vm.startPrank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        vm.expectRevert(IFighterRegistry.NotHuman.selector);
        reg.registerAgent(agent, address(0x22), moveKey, 1e6);
        vm.stopPrank();
    }

    function test_unbindNeverShrinksTheFamily() public {
        _register(human, nullifier);
        vm.startPrank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        reg.unbindAgent(agent);
        vm.expectRevert(IFighterRegistry.AgentIsUnbound.selector);
        reg.unbindAgent(agent);
        vm.expectRevert(IFighterRegistry.AlreadyRegistered.selector);
        reg.registerAgent(human, agent, moveKey, 1e6);
        reg.registerAgent(human, address(0x23), moveKey, 1e6);
        vm.stopPrank();
        assertEq(reg.familySize(human), 3);
        assertEq(reg.stakeCapOf(agent), 0);
        assertTrue(reg.isUnbound(agent));
    }

    function test_raisingACapNeedsAFreshApproval() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        uint64 expiry = uint64(block.timestamp + 60);
        (ApprovalLib.Approval memory a, bytes memory sig) = _approval(human, ApprovalLib.ACTION_RAISE_CAP, keccak256(abi.encode(agent, uint256(2e6))), expiry, 1);
        reg.raiseAgentCap(agent, 2e6, a, sig);
        assertEq(reg.stakeCapOf(agent), 2e6);
    }

    function test_approvalWorksOnlyOnce() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        uint64 expiry = uint64(block.timestamp + 60);
        (ApprovalLib.Approval memory a, bytes memory sig) = _approval(human, ApprovalLib.ACTION_RAISE_CAP, keccak256(abi.encode(agent, uint256(2e6))), expiry, 1);
        reg.raiseAgentCap(agent, 2e6, a, sig);
        vm.expectRevert(ApprovalLib.ApprovalUsed.selector);
        reg.raiseAgentCap(agent, 2e6, a, sig);
    }

    function test_approvalMustMatchTheActionAndParameters() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        uint64 expiry = uint64(block.timestamp + 60);
        (ApprovalLib.Approval memory a, bytes memory sig) = _approval(human, ApprovalLib.ACTION_RAISE_CAP, keccak256(abi.encode(agent, uint256(2e6))), expiry, 1);
        vm.expectRevert(ApprovalLib.BadApproval.selector);
        reg.raiseAgentCap(agent, 3e6, a, sig);
        (a, sig) = _approval(human, ApprovalLib.ACTION_ENROLL, keccak256(abi.encode(agent, uint256(2e6))), expiry, 2);
        vm.expectRevert(ApprovalLib.BadApproval.selector);
        reg.raiseAgentCap(agent, 2e6, a, sig);
        (a, sig) = _approval(address(0x55), ApprovalLib.ACTION_RAISE_CAP, keccak256(abi.encode(agent, uint256(2e6))), expiry, 3);
        vm.expectRevert(ApprovalLib.BadApproval.selector);
        reg.raiseAgentCap(agent, 2e6, a, sig);
    }

    function test_expiredOrForgedApprovalRefused() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        bytes32 h = keccak256(abi.encode(agent, uint256(2e6)));
        (ApprovalLib.Approval memory a, bytes memory sig) = _approval(human, ApprovalLib.ACTION_RAISE_CAP, h, uint64(block.timestamp - 1), 1);
        vm.expectRevert(ApprovalLib.ApprovalExpired.selector);
        reg.raiseAgentCap(agent, 2e6, a, sig);
        a = ApprovalLib.Approval(human, ApprovalLib.ACTION_RAISE_CAP, h, uint64(block.timestamp + 60), 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, reg.approvalDigest(a));
        vm.expectRevert(ApprovalLib.BadApproval.selector);
        reg.raiseAgentCap(agent, 2e6, a, abi.encodePacked(r, s, v));
    }

    function test_cannotRaiseAboveTheSystemMaximum() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        uint256 tooMuch = 10_000_001;
        (ApprovalLib.Approval memory a, bytes memory sig) = _approval(human, ApprovalLib.ACTION_RAISE_CAP, keccak256(abi.encode(agent, tooMuch)), uint64(block.timestamp + 60), 1);
        vm.expectRevert(IFighterRegistry.CapTooHigh.selector);
        reg.raiseAgentCap(agent, tooMuch, a, sig);
    }

    function test_humanLowersCapDirectlyAndOnlyDown() public {
        _register(human, nullifier);
        vm.prank(registrar);
        reg.registerAgent(human, agent, moveKey, 1e6);
        vm.expectRevert(IFighterRegistry.NotOwner.selector);
        reg.lowerAgentCap(agent, 5e5);
        vm.startPrank(human);
        vm.expectRevert(IFighterRegistry.NotLower.selector);
        reg.lowerAgentCap(agent, 2e6);
        reg.lowerAgentCap(agent, 5e5);
        vm.stopPrank();
        assertEq(reg.stakeCapOf(agent), 5e5);
    }

    function test_setMoveKey() public {
        _register(human, nullifier);
        vm.startPrank(human);
        vm.expectRevert(IFighterRegistry.ZeroKey.selector);
        reg.setMoveKey(address(0));
        reg.setMoveKey(address(0x44));
        vm.stopPrank();
        assertEq(reg.moveKeyOf(human), address(0x44));
    }

    function test_unregisteredReverts() public {
        vm.expectRevert(IFighterRegistry.NotRegistered.selector);
        reg.humanOf(address(0x77));
        vm.expectRevert(IFighterRegistry.NotRegistered.selector);
        reg.familySize(address(0x77));
        assertEq(reg.stakeCapOf(address(0x77)), 0);
    }
}
