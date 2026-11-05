// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ApprovalLib} from "../src/ApprovalLib.sol";
import {BackingVault} from "../src/BackingVault.sol";
import {FighterRegistry} from "../src/FighterRegistry.sol";
import {IReferee} from "../src/interfaces/IReferee.sol";
import {MockUSDC} from "./helpers/ArenaBase.sol";

/// @dev Lets a test set any verdict.
contract MockVerdicts {
    mapping(address => IReferee.Verdict) private _v;

    function set(address f, bool skilled, bool lapsed) external {
        _v[f].skilled = skilled;
        _v[f].lapsed = lapsed;
    }

    function verdictOf(address f) external view returns (IReferee.Verdict memory) {
        return _v[f];
    }
}

contract BackingVaultTest is Test {
    BackingVault vault;
    FighterRegistry reg;
    MockVerdicts verdicts;
    MockUSDC usdc;
    uint256 attesterKey = 0xA77E;
    address arena = address(0xA4E4A);
    address fighter;
    address friend = address(0xF1);
    address backer = address(0xB0);
    address other = address(0xB1);
    address opponent = address(0x0F);
    uint256 nextNullifier = 1;
    uint256 duelId = 1;

    function setUp() public {
        vm.warp(1_800_000_000);
        fighter = vm.addr(0xF0);
        usdc = new MockUSDC();
        verdicts = new MockVerdicts();
        reg = new FighterRegistry(vm.addr(attesterKey), address(this), 10_000_000);
        string memory j = vm.readFile("../config/params.json");
        BackingVault.Params memory p = BackingVault.Params({
            maxStakeBps: vm.parseJsonUint(j, ".vault.maxStakeBps"),
            dailyLossBps: vm.parseJsonUint(j, ".vault.dailyLossBps"),
            maxDuelsPerDay: vm.parseJsonUint(j, ".vault.maxDuelsPerDay"),
            fundCooldown: vm.parseJsonUint(j, ".vault.fundCooldownS"),
            feeBps: vm.parseJsonUint(j, ".vault.feeBps"),
            minOwnBps: vm.parseJsonUint(j, ".vault.minOwnBps"),
            forfeitPause: vm.parseJsonUint(j, ".vault.forfeitPauseS")
        });
        vault = new BackingVault(address(usdc), arena, IReferee(address(verdicts)), reg, vm.addr(attesterKey), p);
        _human(fighter);
        _human(friend);
        _human(opponent);
        verdicts.set(fighter, true, false);
        _allow(fighter);
        _fund(backer, 1_000_000_000);
        _fund(other, 1_000_000_000);
        usdc.mint(arena, 1_000_000_000);
    }

    function _human(address who) internal {
        uint256 n = nextNullifier++;
        uint64 expiry = uint64(block.timestamp + 60);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, reg.attestationDigest(who, n, expiry));
        vm.prank(who);
        reg.registerHuman(address(0x1234), n, expiry, abi.encodePacked(r, s, v));
    }

    function _allow(address who) internal {
        ApprovalLib.Approval memory a = ApprovalLib.Approval(who, ApprovalLib.ACTION_ALLOW_BACKING, keccak256(abi.encode(who)), uint64(block.timestamp + 60), nextNullifier++);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, vault.approvalDigest(a));
        vault.allowBacking(who, a, abi.encodePacked(r, s, v));
    }

    function _fund(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _deposit(address who, uint256 amount) internal returns (uint256) {
        vm.prank(who);
        return vault.deposit(fighter, amount);
    }

    function _fundStake(uint256 amount) internal returns (uint256 id) {
        id = duelId++;
        vm.prank(arena);
        vault.fundStake(fighter, id, amount, amount, opponent);
    }

    function _settle(uint256 id, uint256 returned, bool forfeit) internal {
        vm.startPrank(arena);
        usdc.transfer(address(vault), returned);
        vault.onSettle(id, fighter, returned, forfeit);
        vm.stopPrank();
    }

    function _nextDay() internal {
        vm.warp(block.timestamp + 1 days + 1);
    }

    function test_depositOnlyIntoASkilledAndAllowedFighter() public {
        verdicts.set(fighter, false, false);
        vm.prank(backer);
        vm.expectRevert(BackingVault.NotSkilled.selector);
        vault.deposit(fighter, 1000);
        verdicts.set(fighter, true, true);
        vm.prank(backer);
        vm.expectRevert(BackingVault.NotSkilled.selector);
        vault.deposit(fighter, 1000);
        verdicts.set(friend, true, false);
        vm.prank(backer);
        vm.expectRevert(BackingVault.BackingNotAllowed.selector);
        vault.deposit(friend, 1000);
        verdicts.set(fighter, true, false);
        assertGt(_deposit(backer, 1000), 0);
    }

    function test_coinFlipFamilyIsRefused() public {
        // The demo's refusal: a fighter with no verdict can't be backed, whatever it allowed.
        _allow(friend);
        vm.prank(backer);
        vm.expectRevert(BackingVault.NotSkilled.selector);
        vault.deposit(friend, 1000);
    }

    function test_allowBackingNeedsAFreshApprovalForThatFighter() public {
        ApprovalLib.Approval memory a = ApprovalLib.Approval(friend, ApprovalLib.ACTION_ALLOW_BACKING, keccak256(abi.encode(fighter)), uint64(block.timestamp + 60), 99);
        bytes32 digest = vault.approvalDigest(a);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, digest);
        vm.expectRevert(ApprovalLib.BadApproval.selector);
        vault.allowBacking(friend, a, abi.encodePacked(r, s, v));
        a.paramsHash = keccak256(abi.encode(friend));
        digest = vault.approvalDigest(a);
        (v, r, s) = vm.sign(0xBAD, digest);
        vm.expectRevert(ApprovalLib.BadApproval.selector);
        vault.allowBacking(friend, a, abi.encodePacked(r, s, v));
        (v, r, s) = vm.sign(attesterKey, digest);
        vault.allowBacking(friend, a, abi.encodePacked(r, s, v));
        vm.expectRevert(ApprovalLib.ApprovalUsed.selector);
        vault.allowBacking(friend, a, abi.encodePacked(r, s, v));
    }

    function test_firstDepositorInflationFails() public {
        _deposit(backer, 1);
        vm.prank(backer);
        usdc.transfer(address(vault), 100_000_000);
        uint256 shares = _deposit(other, 10_000_000);
        assertGt(shares, 0);
        assertApproxEqAbs(vault.assetsOf(fighter, other), 10_000_000, 10);
    }

    function test_withdrawPaysTheCallerOnly() public {
        uint256 shares = _deposit(backer, 1_000_000);
        uint256 bal = usdc.balanceOf(backer);
        vm.prank(other);
        vm.expectRevert(BackingVault.InsufficientShares.selector);
        vault.withdraw(fighter, shares);
        vm.prank(backer);
        vault.withdraw(fighter, shares);
        assertApproxEqAbs(usdc.balanceOf(backer), bal + 1_000_000, 1);
    }

    function test_onlyArenaFundsAndSettles() public {
        vm.expectRevert(BackingVault.NotArena.selector);
        vault.fundStake(fighter, 1, 1, 1, opponent);
        vm.expectRevert(BackingVault.NotArena.selector);
        vault.onSettle(1, fighter, 0, false);
    }

    function test_fundingRules() public {
        _deposit(backer, 100_000_000);
        vm.startPrank(arena);
        vm.expectRevert(BackingVault.StakeTooLarge.selector);
        vault.fundStake(fighter, 1, 5_000_001, 5_000_001, opponent);
        vm.expectRevert(BackingVault.OwnStakeTooSmall.selector);
        vault.fundStake(fighter, 1, 1_000_000, 300_000, opponent);
        vm.expectRevert(BackingVault.ZeroAmount.selector);
        vault.fundStake(fighter, 1, 0, 0, opponent);
        vm.stopPrank();
        verdicts.set(opponent, true, false);
        vm.prank(arena);
        vm.expectRevert(BackingVault.OpponentSkilled.selector);
        vault.fundStake(fighter, 1, 1_000_000, 1_000_000, opponent);
        verdicts.set(opponent, false, false);
        verdicts.set(fighter, false, false);
        vm.prank(arena);
        vm.expectRevert(BackingVault.NotSkilled.selector);
        vault.fundStake(fighter, 1, 1_000_000, 1_000_000, opponent);
    }

    function test_sameFamilyOpponentRefused() public {
        _deposit(backer, 100_000_000);
        vm.prank(address(this));
        reg.registerAgent(fighter, address(0xAA), address(0x1234), 1_000_000);
        vm.prank(arena);
        vm.expectRevert(BackingVault.SameFamily.selector);
        vault.fundStake(fighter, 1, 1_000_000, 1_000_000, address(0xAA));
    }

    function test_oneLiveDuelLocksEverything() public {
        uint256 shares = _deposit(backer, 100_000_000);
        uint256 id = _fundStake(1_000_000);
        vm.prank(arena);
        vm.expectRevert(BackingVault.DuelLive.selector);
        vault.fundStake(fighter, id + 1, 1_000_000, 1_000_000, opponent);
        vm.prank(backer);
        vm.expectRevert(BackingVault.DuelLive.selector);
        vault.withdraw(fighter, shares);
        vm.prank(other);
        vm.expectRevert(BackingVault.DuelLive.selector);
        vault.deposit(fighter, 1000);
    }

    function test_unknownDuelRefused() public {
        _deposit(backer, 100_000_000);
        _fundStake(1_000_000);
        vm.prank(arena);
        vm.expectRevert(BackingVault.UnknownDuel.selector);
        vault.onSettle(99, fighter, 0, false);
    }

    function test_cooldownBetweenFundedDuels() public {
        _deposit(backer, 100_000_000);
        uint256 id = _fundStake(1_000_000);
        _settle(id, 1_000_000, false);
        vm.prank(arena);
        vm.expectRevert(BackingVault.Cooldown.selector);
        vault.fundStake(fighter, id + 1, 1_000_000, 1_000_000, opponent);
        vm.warp(block.timestamp + vault.FUND_COOLDOWN());
        duelId = id + 1;
        _fundStake(1_000_000);
    }

    function test_winPaysVaultAndMintsFeeAboveTheHighWaterMark() public {
        _deposit(backer, 100_000_000);
        uint256 hwm = vault.highWaterMark(fighter);
        assertGt(hwm, 0);
        uint256 id = _fundStake(1_000_000);
        _settle(id, 1_960_000, false);
        assertGt(vault.highWaterMark(fighter), hwm);
        assertGt(vault.sharesOf(fighter, fighter), 0, "fee shares to the fighter");
        assertGt(vault.assetsOf(fighter, backer), 100_000_000);
    }

    function test_lossThenRecoveryChargesNoFee() public {
        _deposit(backer, 100_000_000);
        uint256 hwm = vault.highWaterMark(fighter);
        uint256 id = _fundStake(1_000_000);
        _settle(id, 0, false);
        assertEq(vault.highWaterMark(fighter), hwm);
        vm.warp(block.timestamp + vault.FUND_COOLDOWN());
        id = _fundStake(1_000_000);
        _settle(id, 1_500_000, false);
        assertEq(vault.highWaterMark(fighter), hwm, "partial recovery leaves the mark");
        assertEq(vault.sharesOf(fighter, fighter), 0);
    }

    function test_drawRefundsWithNoLossRecorded() public {
        _deposit(backer, 100_000_000);
        uint256 id = _fundStake(1_000_000);
        _settle(id, 1_000_000, false);
        (uint256 loss, uint256 count) = vault.rolling(fighter);
        assertEq(loss, 0);
        assertEq(count, 1);
        assertApproxEqAbs(vault.assetsOf(fighter, backer), 100_000_000, 1);
    }

    function test_dailyLossCap() public {
        _deposit(backer, 100_000_000);
        bool capped;
        for (uint256 i; i < 10 && !capped; ++i) {
            (uint256 assets,,,) = vault.vaultOf(fighter);
            uint256 amount = (assets * vault.MAX_STAKE_BPS()) / 10_000;
            uint256 id = duelId++;
            vm.prank(arena);
            try vault.fundStake(fighter, id, amount, amount, opponent) {
                _settle(id, 0, false);
                vm.warp(block.timestamp + vault.FUND_COOLDOWN());
            } catch (bytes memory err) {
                assertEq(bytes4(err), BackingVault.DailyLossCap.selector);
                capped = true;
            }
        }
        assertTrue(capped);
        _nextDay();
        _fundStake(1_000);
    }

    function test_duelCountIsCappedPerDay() public {
        _deposit(backer, 1_000_000_000);
        for (uint256 i; i < vault.MAX_DUELS_PER_DAY(); ++i) {
            uint256 id = _fundStake(1000);
            _settle(id, 1000, false);
            vm.warp(block.timestamp + vault.FUND_COOLDOWN());
        }
        vm.prank(arena);
        vm.expectRevert(BackingVault.TooManyDuels.selector);
        vault.fundStake(fighter, duelId, 1000, 1000, opponent);
    }

    function test_attack_thrownDuelPausesTheVault() public {
        // A backed fighter forfeits to a friend to walk off with the vault's stake: it works once, then stops.
        _deposit(backer, 100_000_000);
        uint256 id = _fundStake(1_000_000);
        _settle(id, 0, true);
        vm.warp(block.timestamp + vault.FUND_COOLDOWN());
        vm.prank(arena);
        vm.expectRevert(BackingVault.Paused.selector);
        vault.fundStake(fighter, id + 1, 1_000_000, 1_000_000, opponent);
        vm.warp(block.timestamp + vault.FORFEIT_PAUSE());
        duelId = id + 1;
        _fundStake(1_000_000);
    }

    function test_attacker_cannotDrain() public {
        _deposit(backer, 100_000_000);
        address attacker = address(0xBAD);
        vm.startPrank(attacker);
        vm.expectRevert(BackingVault.InsufficientShares.selector);
        vault.withdraw(fighter, 1);
        vm.expectRevert(BackingVault.NotArena.selector);
        vault.fundStake(fighter, 1, 1000, 1000, opponent);
        vm.expectRevert(BackingVault.NotArena.selector);
        vault.onSettle(1, fighter, 0, false);
        vm.stopPrank();
    }

    function test_paramsAreChecked() public {
        BackingVault.Params memory p = BackingVault.Params(10_001, 2000, 32, 120, 2000, 2500, 86400);
        vm.expectRevert(BackingVault.BadParams.selector);
        new BackingVault(address(usdc), arena, IReferee(address(verdicts)), reg, vm.addr(attesterKey), p);
        p = BackingVault.Params(500, 2000, 0, 120, 2000, 2500, 86400);
        vm.expectRevert(BackingVault.BadParams.selector);
        new BackingVault(address(usdc), arena, IReferee(address(verdicts)), reg, vm.addr(attesterKey), p);
    }

    function testFuzz_booksMatchBalance(uint96 dep, uint96 returned) public {
        uint256 d = bound(dep, 10_000, 1_000_000_000);
        _deposit(backer, d);
        uint256 amount = (d * vault.MAX_STAKE_BPS()) / 10_000;
        vm.assume(amount > 0);
        uint256 id = _fundStake(amount);
        uint256 r = bound(returned, 0, 2 * amount);
        _settle(id, r, false);
        (uint256 assets,,,) = vault.vaultOf(fighter);
        assertEq(usdc.balanceOf(address(vault)), assets);
    }
}
