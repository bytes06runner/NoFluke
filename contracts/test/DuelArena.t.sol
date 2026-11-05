// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythErrors} from "@pythnetwork/pyth-sdk-solidity/PythErrors.sol";
import {DuelArena} from "../src/DuelArena.sol";
import {FightMath as F} from "../src/FightMath.sol";
import {IBackingVault} from "../src/interfaces/IBackingVault.sol";
import {IReferee} from "../src/interfaces/IReferee.sol";
import {ArenaBase} from "./helpers/ArenaBase.sol";

contract DuelArenaTest is ArenaBase {
    int64 constant BIG = 20_000_000; // z = 2 at SIGMA and P0: the capped hit
    int64 constant SMALL = 500_000; // z = 0.05: one point of difference

    function setUp() public {
        _deploy(IBackingVault(address(0)));
    }

    // ------------------------------------------------------------ happy paths

    function test_koPaysWinnerMinusRake() public {
        uint256 id = _duel(STAKE);
        uint256 balA = usdc.balanceOf(a);
        uint256 balB = usdc.balanceOf(b);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        _settle(id, _updates(id, _bumps(2, BIG)));
        uint256 rake_ = (2 * uint256(STAKE) * arena.RAKE_BPS()) / 10_000;
        assertEq(usdc.balanceOf(a), balA + 2 * uint256(STAKE) - rake_);
        assertEq(usdc.balanceOf(b), balB);
        assertEq(usdc.balanceOf(rake), rake_);
        assertEq(usdc.balanceOf(address(arena)), 0);
        assertEq(uint8(arena.duel(id).status), uint8(DuelArena.Status.Settled));
    }

    function test_winOnHpAfterFiveRounds() public {
        uint256 id = _duel(STAKE);
        for (uint8 r = 1; r <= 5; ++r) _play(id, r, UP, DOWN);
        vm.expectEmit(true, false, false, true);
        emit DuelArena.DuelSettled(id, 1, F.REASON_HP, 5, 2 * uint256(STAKE) - (2 * uint256(STAKE) * arena.RAKE_BPS()) / 10_000, (2 * uint256(STAKE) * arena.RAKE_BPS()) / 10_000);
        bytes[] memory u = _updates(id, _bumps(5, SMALL));
        vm.warp(arena.revealDeadline(id) + 1);
        arena.settle{value: _fee(u)}(id, u);
    }

    function test_oneUpdateServesAsEndAndNextStart() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 5; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(5, SMALL));
        assertEq(u.length, 6);
        vm.warp(arena.revealDeadline(id) + 1);
        uint256 balBefore = address(this).balance;
        arena.settle{value: _fee(u)}(id, u);
        assertEq(balBefore - address(this).balance, _fee(u), "fee for six updates, not ten");
    }

    function test_freeDuelSettlesWithoutMoney() public {
        uint256 id = _duel(0);
        uint256 balA = usdc.balanceOf(a);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        _settle(id, _updates(id, _bumps(2, BIG)));
        assertEq(usdc.balanceOf(a), balA);
        assertEq(usdc.balanceOf(rake), 0);
    }

    function test_excessFeeRefunded() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        vm.warp(arena.revealDeadline(id) + 1);
        uint256 before = address(this).balance;
        arena.settle{value: _fee(u) + 1 ether}(id, u);
        assertEq(before - address(this).balance, _fee(u));
    }

    function test_insufficientFeeReverts() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        vm.warp(arena.revealDeadline(id) + 1);
        vm.expectRevert(DuelArena.InsufficientFee.selector);
        arena.settle{value: 0}(id, u);
    }

    function test_settleTwiceReverts() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        _settle(id, u);
        uint256 fee = _fee(u);
        vm.expectRevert(DuelArena.WrongStatus.selector);
        arena.settle{value: fee}(id, u);
    }

    function test_refereeRatesBothFightersPerScoredRound() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        _settle(id, _updates(id, _bumps(2, BIG)));
        assertEq(ref.verdictOf(a).rounds, 2);
        assertEq(ref.verdictOf(b).rounds, 2);
    }

    // ------------------------------------------------------------ early and late settling

    function test_cannotSettleBeforePricesAreFinal() public {
        uint256 id = _duel(0);
        _play(id, 1, UP, DOWN);
        _play(id, 2, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        vm.warp(arena.tStart(id, 2) + slot + window - 1);
        uint256 fee = _fee(u);
        vm.expectRevert(DuelArena.NotFinal.selector);
        arena.settle{value: fee}(id, u);
        vm.warp(arena.tStart(id, 2) + slot + window);
        arena.settle{value: fee}(id, u);
    }

    function test_cannotSettleBeforeAFutureRoundsBell() public {
        // A leader cannot settle after one good round: the next round has not rung, so the match is not over.
        uint256 id = _duel(0);
        _play(id, 1, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(1, SMALL));
        vm.warp(arena.tStart(id, 2) - 1);
        uint256 fee = _fee(u);
        vm.expectRevert(DuelArena.NotFinal.selector);
        arena.settle{value: fee}(id, u);
    }

    function test_stoppingEarlyIsAForfeitNotAWinOnHp() public {
        // Both sides stop after a round: both forfeit the next one, so a lead from round 1 wins nothing.
        uint256 id = _duel(STAKE);
        uint256 balA = usdc.balanceOf(a);
        _play(id, 1, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(1, SMALL));
        vm.warp(arena.tStart(id, 2) + slot + window);
        uint256 fee = _fee(u);
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, 0, F.REASON_FORFEIT, 2, 0, 0);
        arena.settle{value: fee}(id, u);
        assertEq(usdc.balanceOf(a), balA + STAKE);
    }

    function test_suddenDeathAfterTie() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 5; ++r) _play(id, r, GUARD, GUARD);
        _play(id, 6, UP, DOWN);
        int64[] memory bumps = new int64[](6);
        bumps[5] = SMALL;
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, 1, F.REASON_HP, 6, 0, 0);
        _settle(id, _updates(id, bumps));
    }

    function test_suddenDeathTieRefundsBoth() public {
        uint256 id = _duel(STAKE);
        uint256 balA = usdc.balanceOf(a);
        uint256 balB = usdc.balanceOf(b);
        for (uint8 r = 1; r <= 6; ++r) _play(id, r, GUARD, GUARD);
        _settle(id, _updates(id, new int64[](6)));
        assertEq(usdc.balanceOf(a), balA + STAKE);
        assertEq(usdc.balanceOf(b), balB + STAKE);
        assertEq(usdc.balanceOf(rake), 0);
    }

    // ------------------------------------------------------------ forfeits

    function test_missingCommitForfeitsAtTheBell() public {
        uint256 id = _duel(STAKE);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 cb = _hash(id, 1, b, DOWN, 0, false);
        arena.anchorOwn(id, 1, 1, cb, _sig(id, 1, cb, bMove));
        vm.warp(arena.tStart(id, 1));
        _reveal(id, 1, 1, DOWN);
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, 2, F.REASON_FORFEIT, 1, 0, 0);
        arena.settle(id, new bytes[](0));
    }

    function test_missingRevealForfeitsOnlyAfterDeadline() public {
        uint256 id = _duel(STAKE);
        _anchorBoth(id, 1, UP, DOWN);
        _reveal(id, 1, 1, DOWN);
        vm.warp(arena.revealDeadline(id));
        vm.expectRevert(DuelArena.NotFinal.selector);
        arena.settle(id, new bytes[](0));
        vm.warp(arena.revealDeadline(id) + 1);
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, 2, F.REASON_FORFEIT, 1, 0, 0);
        arena.settle(id, new bytes[](0));
    }

    function test_invalidMoveForfeits() public {
        uint256 id = _duel(0);
        _anchorBoth(id, 1, 9, DOWN);
        _reveal(id, 1, 0, 9);
        _reveal(id, 1, 1, DOWN);
        vm.warp(arena.tStart(id, 1));
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, 2, F.REASON_FORFEIT, 1, 0, 0);
        arena.settle(id, new bytes[](0));
    }

    function test_bothForfeitIsADrawWithNoRake() public {
        uint256 id = _duel(STAKE);
        uint256 balA = usdc.balanceOf(a);
        vm.warp(arena.tStart(id, 1));
        arena.settle(id, new bytes[](0));
        assertEq(usdc.balanceOf(a), balA + STAKE);
        assertEq(usdc.balanceOf(rake), 0);
    }

    function test_forfeitCountsAgainstTheRefereeOnlyForTheForfeiter() public {
        uint256 id = _duel(0);
        _anchorBoth(id, 1, UP, DOWN);
        _reveal(id, 1, 1, DOWN);
        vm.warp(arena.revealDeadline(id) + 1);
        arena.settle(id, new bytes[](0));
        assertEq(ref.verdictOf(a).rounds, 1);
        assertEq(ref.verdictOf(b).rounds, 0);
    }

    // ------------------------------------------------------------ attacks found in design review

    function test_attack_fighterCannotBeInTwoLiveDuels_noHedging() public {
        // Four overlapping duels with all four moves, then settling only the winner, would fake any verdict.
        uint256 first = _duel(0);
        uint256 second = _create(a, 0, address(0));
        _approve(c);
        vm.prank(c);
        vm.expectRevert(DuelArena.FighterBusy.selector);
        arena.joinDuel(second, noPermit, 0);
        assertEq(arena.activeDuel(a), first);
    }

    function test_liveDuelEndsBusyStatusAtSettle() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1));
        arena.settle(id, new bytes[](0));
        assertEq(arena.activeDuel(a), 0);
        assertEq(arena.activeDuel(b), 0);
    }

    function test_attack_refusingToSettleALossChargesBothFighters() public {
        uint256 id = _duel(STAKE);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        vm.warp(arena.revealDeadline(id) + arena.REFUND_GRACE() + 1);
        arena.refundExpired(id);
        IReferee.Verdict memory va = ref.verdictOf(a);
        assertEq(va.rounds, arena.REGULAR_ROUNDS());
        assertEq(ref.verdictOf(b).rounds, arena.REGULAR_ROUNDS());
        assertLe(va.logW, 0);
    }

    function test_attack_lateRevealDoesNotStealAMatchFromAClientThatKeepsPlaying() public {
        // The withholder reveals round 1 late, but the honest side kept committing, so nobody forfeits unfairly.
        uint256 id = _duel(STAKE);
        _anchorBoth(id, 1, UP, DOWN);
        _reveal(id, 1, 1, DOWN);
        _anchorBoth(id, 2, UP, DOWN);
        _reveal(id, 2, 1, DOWN);
        _reveal(id, 2, 0, UP);
        _reveal(id, 1, 0, UP);
        bytes[] memory u = _updates(id, _bumps(2, -BIG));
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, 2, F.REASON_KO, 2, 0, 0);
        _settle(id, u);
    }

    function test_roundStartsSitOnTheSharedGrid() public {
        for (uint256 i; i < 40; ++i) {
            vm.warp(block.timestamp + 7);
            uint256 id = _create(a, 0, c);
            _join(c, id);
            assertEq(arena.duel(id).startAt % slot, 0);
            assertGe(arena.duel(id).startAt, block.timestamp + arena.START_DELAY());
            vm.warp(arena.tStart(id, 1));
            arena.settle(id, new bytes[](0));
        }
    }

    // ------------------------------------------------------------ commit and reveal rules

    function test_wrongCommitSignatureReverts() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes memory sig = _sig(id, 1, ca, bMove);
        vm.expectRevert(DuelArena.BadCommitSignature.selector);
        arena.anchorOwn(id, 1, 0, ca, sig);
    }

    function test_lateAnchorReverts() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1));
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes memory sig = _sig(id, 1, ca, aMove);
        vm.expectRevert(DuelArena.TooLate.selector);
        arena.anchorOwn(id, 1, 0, ca, sig);
        vm.expectRevert(DuelArena.TooLate.selector);
        arena.anchor(id, 1, ca, sig, bytes32(0), "");
    }

    function test_batchAnchorSkipsABadSideSoOneFighterCannotBreakIt() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes32 cb = _hash(id, 1, b, UP, 0, false);
        arena.anchor(id, 1, ca, _sig(id, 1, ca, aMove), cb, _sig(id, 1, cb, aMove));
        assertEq(arena.commitOf(id, 1, 0), ca);
        assertEq(arena.commitOf(id, 1, 1), bytes32(0));
        // Already anchored and bad signature on the other side: nothing lands, so it reverts.
        bytes memory bad = _sig(id, 1, cb, aMove);
        bytes memory sigA = _sig(id, 1, ca, aMove);
        vm.expectRevert(DuelArena.NothingAnchored.selector);
        arena.anchor(id, 1, ca, sigA, cb, bad);
    }

    function test_anchorOwnRules() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes memory sig = _sig(id, 1, ca, aMove);
        vm.expectRevert(DuelArena.EmptyCommit.selector);
        arena.anchorOwn(id, 1, 0, bytes32(0), sig);
        vm.expectRevert(DuelArena.BadSide.selector);
        arena.anchorOwn(id, 1, 2, ca, sig);
        vm.expectRevert(DuelArena.BadRound.selector);
        arena.anchorOwn(id, 0, 0, ca, sig);
        vm.expectRevert(DuelArena.BadRound.selector);
        arena.anchorOwn(id, 7, 0, ca, sig);
        arena.anchorOwn(id, 1, 0, ca, sig);
        vm.expectRevert(DuelArena.AlreadyCommitted.selector);
        arena.anchorOwn(id, 1, 0, ca, sig);
    }

    function test_commitCannotBeReplayedInAnotherRoundOrDuel() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes memory sig = _sig(id, 1, ca, aMove);
        vm.expectRevert(DuelArena.BadCommitSignature.selector);
        arena.anchorOwn(id, 2, 0, ca, sig);
    }

    function test_wrongRevealReverts() public {
        uint256 id = _duel(0);
        _anchorBoth(id, 1, UP, DOWN);
        vm.expectRevert(DuelArena.RevealMismatch.selector);
        _reveal(id, 1, 0, DOWN);
        vm.expectRevert(DuelArena.RevealMismatch.selector);
        arena.reveal(id, 1, 0, UP, 0, false, bytes32(uint256(99)));
        _reveal(id, 1, 0, UP);
        vm.expectRevert(DuelArena.AlreadyRevealed.selector);
        _reveal(id, 1, 0, UP);
    }

    function test_revealRefusedWhileOpponentCanStillReply() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        arena.anchorOwn(id, 1, 0, ca, _sig(id, 1, ca, aMove));
        vm.expectRevert(DuelArena.RevealTooEarly.selector);
        _reveal(id, 1, 0, UP);
        vm.warp(arena.tStart(id, 1));
        _reveal(id, 1, 0, UP);
    }

    function test_revealWithoutCommitAndAfterDeadlineRevert() public {
        uint256 id = _duel(0);
        vm.expectRevert(DuelArena.NoCommit.selector);
        _reveal(id, 1, 0, UP);
        _anchorBoth(id, 1, UP, DOWN);
        vm.warp(arena.revealDeadline(id) + 1);
        vm.expectRevert(DuelArena.TooLate.selector);
        _reveal(id, 1, 0, UP);
    }

    // ------------------------------------------------------------ prices

    function test_forgedPriceWrongTimeReverts() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        uint64 t = arena.tStart(id, 1);
        u[0] = pyth.createPriceFeedUpdateData(feed, P0, 1, EXPO, P0, 1, t + window + 1, t - 1);
        vm.warp(arena.revealDeadline(id) + 1);
        uint256 fee = _fee(u);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        arena.settle{value: fee}(id, u);
    }

    function test_forgedPriceWrongFeedReverts() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        uint64 t = arena.tStart(id, 1);
        u[0] = pyth.createPriceFeedUpdateData(bytes32(uint256(5)), P0, 1, EXPO, P0, 1, t, t - 1);
        vm.warp(arena.revealDeadline(id) + 1);
        uint256 fee = _fee(u);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        arena.settle{value: fee}(id, u);
    }

    function test_laterUpdateInWindowCannotBeCherryPicked() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        uint64 t = arena.tStart(id, 1);
        // Inside the window, but its previous update was already after t, so it is not the first.
        u[0] = pyth.createPriceFeedUpdateData(feed, P0 * 2, 1, EXPO, P0 * 2, 1, t + 3, t + 1);
        vm.warp(arena.revealDeadline(id) + 1);
        uint256 fee = _fee(u);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        arena.settle{value: fee}(id, u);
    }

    function test_missingUpdateRevertsWithoutAVoidProof() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        bytes[] memory u = _updates(id, _bumps(2, BIG));
        u[1] = "";
        vm.warp(arena.revealDeadline(id) + 1);
        uint256 fee = _fee(u);
        vm.expectRevert(DuelArena.MissingPriceUpdate.selector);
        arena.settle{value: fee}(id, u);
    }

    function test_confidenceBackstopVoidsOnlyDislocations() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 6; ++r) _play(id, r, GUARD, GUARD);
        bytes[] memory u = _updates(id, new int64[](6));
        uint64 t = arena.tStart(id, 2);
        // conf 1% is exactly at the cap: scored. One unit over: both rounds touching this boundary are void.
        u[1] = pyth.createPriceFeedUpdateData(feed, P0, uint64(uint256(int256(P0)) / 100 + 1), EXPO, P0, 1, t, t - 1);
        _settle(id, u);
        assertEq(ref.verdictOf(a).rounds, 4, "rounds 1 and 2 void");
    }

    function test_voidRoundIsNotRated() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 6; ++r) _play(id, r, GUARD, GUARD);
        bytes[] memory u = _updates(id, new int64[](6));
        uint64 t = arena.tStart(id, 1);
        u[0] = pyth.createPriceFeedUpdateData(feed, -1, 1, EXPO, P0, 1, t, t - 1);
        _settle(id, u);
        assertEq(ref.verdictOf(a).rounds, 5, "only round 1 touches boundary 0");
    }

    // ------------------------------------------------------------ void proofs

    function _stale(uint256 id, uint8 boundary) internal view returns (bytes memory) {
        uint64 t = arena.tStart(id, boundary + 1);
        return pyth.createPriceFeedUpdateData(feed, P0, 1, EXPO, P0, 1, t + window + 1, t - 1);
    }

    function test_voidBeforeDeadlineReverts() public {
        uint256 id = _duel(0);
        bytes memory proof = _stale(id, 1);
        vm.warp(arena.settleDeadline(id));
        vm.expectRevert(DuelArena.TooEarly.selector);
        arena.voidBoundary{value: 1 ether}(id, 1, proof);
    }

    function test_pricedBoundaryCannotBeVoided() public {
        uint256 id = _duel(0);
        uint64 t = arena.tStart(id, 2);
        bytes memory inWindow = pyth.createPriceFeedUpdateData(feed, P0, 1, EXPO, P0, 1, t + window, t - 1);
        bytes memory notFirst = pyth.createPriceFeedUpdateData(feed, P0, 1, EXPO, P0, 1, t + window + 5, t + 1);
        vm.warp(arena.settleDeadline(id) + 1);
        vm.expectRevert(DuelArena.NotStale.selector);
        arena.voidBoundary{value: 1 ether}(id, 1, inWindow);
        vm.expectRevert(PythErrors.PriceFeedNotFoundWithinRange.selector);
        arena.voidBoundary{value: 1 ether}(id, 1, notFirst);
    }

    function test_voidTwiceOrBadBoundaryReverts() public {
        uint256 id = _duel(0);
        bytes memory proof = _stale(id, 1);
        vm.warp(arena.settleDeadline(id) + 1);
        vm.expectRevert(DuelArena.BadRound.selector);
        arena.voidBoundary{value: 1 ether}(id, 7, proof);
        arena.voidBoundary{value: 1 ether}(id, 1, proof);
        vm.expectRevert(DuelArena.AlreadyVoided.selector);
        arena.voidBoundary{value: 1 ether}(id, 1, proof);
    }

    function test_missingUpdateVoidedAndTheMatchGoesOn() public {
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 6; ++r) _play(id, r, UP, DOWN);
        bytes memory proof = _stale(id, 1);
        vm.warp(arena.settleDeadline(id) + 1);
        arena.voidBoundary{value: 1 ether}(id, 1, proof);
        int64[] memory bumps = _bumps(6, SMALL);
        bytes[] memory u = _updates(id, bumps);
        u[1] = "";
        uint256 fee = _fee(u);
        arena.settle{value: fee}(id, u);
        assertEq(ref.verdictOf(a).rounds, 3, "rounds 1 and 2 void, match still ends after five");
    }

    function test_settledDuelCannotBeVoided() public {
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1));
        arena.settle(id, new bytes[](0));
        vm.expectRevert(DuelArena.WrongStatus.selector);
        arena.voidBoundary{value: 1 ether}(id, 1, "");
    }

    // ------------------------------------------------------------ joining and money

    function test_sameFamilyRejected() public {
        address agent = address(0xA6);
        vm.prank(registrar);
        reg.registerAgent(a, agent, vm.addr(aMove), STAKE);
        uint256 id = _create(a, 0, address(0));
        _approve(agent);
        vm.prank(agent);
        vm.expectRevert(DuelArena.SameFamily.selector);
        arena.joinDuel(id, noPermit, 0);
    }

    function test_agentStakeAboveCapRejectedAtCreateAndJoin() public {
        address agent = address(0xA6);
        vm.prank(registrar);
        reg.registerAgent(a, agent, vm.addr(aMove), STAKE);
        usdc.mint(agent, 10 * uint256(STAKE));
        _approve(agent);
        vm.startPrank(agent);
        vm.expectRevert(DuelArena.AgentCapExceeded.selector);
        arena.createDuel(feed, SIGMA, STAKE + 1, address(0), uint64(block.timestamp + 60), noPermit);
        vm.stopPrank();
        uint256 id = _create(b, STAKE + 1, address(0));
        vm.prank(agent);
        vm.expectRevert(DuelArena.AgentCapExceeded.selector);
        arena.joinDuel(id, noPermit, 0);
    }

    function test_joinRechecksTheCreatorsCap() public {
        address agent = address(0xA6);
        vm.prank(registrar);
        reg.registerAgent(a, agent, vm.addr(aMove), STAKE);
        usdc.mint(agent, 10 * uint256(STAKE));
        uint256 id = _create(agent, STAKE, address(0));
        vm.prank(a);
        reg.lowerAgentCap(agent, 0);
        _approve(b);
        vm.prank(b);
        vm.expectRevert(DuelArena.AgentCapExceeded.selector);
        arena.joinDuel(id, noPermit, 0);
    }

    function test_unboundAgentRefusedAtAnyStake() public {
        address agent = address(0xA6);
        vm.startPrank(registrar);
        reg.registerAgent(a, agent, vm.addr(aMove), STAKE);
        reg.unbindAgent(agent);
        vm.stopPrank();
        vm.prank(agent);
        vm.expectRevert(DuelArena.AgentUnbound.selector);
        arena.createDuel(feed, SIGMA, 0, address(0), uint64(block.timestamp + 60), noPermit);
    }

    function test_createBounds() public {
        _approve(a);
        vm.startPrank(a);
        uint64 joinBy = uint64(block.timestamp + 60);
        vm.expectRevert(DuelArena.UnsupportedFeed.selector);
        arena.createDuel(bytes32(uint256(1)), SIGMA, 0, address(0), joinBy, noPermit);
        vm.expectRevert(F.SigmaBounds.selector);
        arena.createDuel(feed, 99, 0, address(0), joinBy, noPermit);
        vm.expectRevert(F.SigmaBounds.selector);
        arena.createDuel(feed, 5001, 0, address(0), joinBy, noPermit);
        uint96 tooMuch = uint96(arena.MAX_STAKE() + 1);
        vm.expectRevert(DuelArena.StakeTooHigh.selector);
        arena.createDuel(feed, SIGMA, tooMuch, address(0), joinBy, noPermit);
        vm.expectRevert(DuelArena.BadJoinWindow.selector);
        arena.createDuel(feed, SIGMA, 0, address(0), uint64(block.timestamp), noPermit);
        uint64 far = uint64(block.timestamp + arena.MAX_JOIN_WINDOW() + 1);
        vm.expectRevert(DuelArena.BadJoinWindow.selector);
        arena.createDuel(feed, SIGMA, 0, address(0), far, noPermit);
        vm.stopPrank();
    }

    function test_unregisteredCannotCreate() public {
        vm.prank(address(0x5555));
        vm.expectRevert(DuelArena.NotRegistered.selector);
        arena.createDuel(feed, SIGMA, 0, address(0), uint64(block.timestamp + 60), noPermit);
    }

    function test_stakeAboveUnverifiedCapNeedsBothSkilled() public {
        uint96 big = uint96(arena.UNVERIFIED_STAKE_CAP() + 1);
        uint256 id = _create(a, big, address(0));
        _approve(b);
        vm.prank(b);
        vm.expectRevert(DuelArena.NeedsSkilled.selector);
        arena.joinDuel(id, noPermit, 0);
    }

    function test_joinRules() public {
        uint256 id = _create(a, 0, b);
        vm.prank(a);
        vm.expectRevert(DuelArena.NotFighter.selector);
        arena.joinDuel(id, noPermit, 0);
        vm.prank(c);
        vm.expectRevert(DuelArena.NotFighter.selector);
        arena.joinDuel(id, noPermit, 0);
        vm.warp(arena.duel(id).joinBy + 1);
        vm.prank(b);
        vm.expectRevert(DuelArena.JoinClosed.selector);
        arena.joinDuel(id, noPermit, 0);
    }

    function test_cancelUnjoinedAfterExpiry() public {
        uint256 bal = usdc.balanceOf(a);
        uint256 id = _create(a, STAKE, address(0));
        assertEq(usdc.balanceOf(a), bal - STAKE);
        vm.expectRevert(DuelArena.TooEarly.selector);
        arena.cancel(id);
        vm.warp(arena.duel(id).joinBy + 1);
        arena.cancel(id);
        assertEq(usdc.balanceOf(a), bal);
        vm.expectRevert(DuelArena.WrongStatus.selector);
        arena.cancel(id);
    }

    function test_refundExpiredRefundsBothAndOnlyAfterGrace() public {
        uint256 id = _duel(STAKE);
        uint256 balA = usdc.balanceOf(a);
        uint256 balB = usdc.balanceOf(b);
        vm.warp(arena.revealDeadline(id) + arena.REFUND_GRACE());
        vm.expectRevert(DuelArena.TooEarly.selector);
        arena.refundExpired(id);
        vm.warp(arena.revealDeadline(id) + arena.REFUND_GRACE() + 1);
        arena.refundExpired(id);
        assertEq(usdc.balanceOf(a), balA + STAKE);
        assertEq(usdc.balanceOf(b), balB + STAKE);
        assertEq(arena.activeDuel(a), 0);
    }

    function test_blacklistedWinnerCannotBlockSettlement() public {
        uint256 id = _duel(STAKE);
        for (uint8 r = 1; r <= 2; ++r) _play(id, r, UP, DOWN);
        usdc.setBlacklisted(a, true);
        _settle(id, _updates(id, _bumps(2, BIG)));
        assertEq(uint8(arena.duel(id).status), uint8(DuelArena.Status.Settled));
        uint256 owed = arena.owed(a);
        assertGt(owed, 0);
        usdc.setBlacklisted(a, false);
        uint256 bal = usdc.balanceOf(a);
        vm.prank(a);
        arena.claim();
        assertEq(usdc.balanceOf(a), bal + owed);
        vm.prank(a);
        vm.expectRevert(DuelArena.NothingOwed.selector);
        arena.claim();
    }

    function test_constructorRejectsParamsThatBreakTheSchedule() public {
        string memory j = vm.readFile("../config/params.json");
        DuelArena.Params memory p = _params(j);
        p.priceWindow = p.revealGrace + 1;
        bytes32[] memory feeds = new bytes32[](0);
        int64[] memory cs = new int64[](0);
        F.Rules memory r = _rules(j);
        vm.expectRevert(DuelArena.BadParams.selector);
        new DuelArena(IPyth(address(pyth)), address(usdc), reg, IReferee(address(ref)), IBackingVault(address(0)), rake, p, r, feeds, cs);
        p = _params(j);
        p.tape = p.slot - 1;
        vm.expectRevert(DuelArena.BadParams.selector);
        new DuelArena(IPyth(address(pyth)), address(usdc), reg, IReferee(address(ref)), IBackingVault(address(0)), rake, p, r, feeds, cs);
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_anchorOnlyBeforeTheBell(uint64 offset) public {
        uint256 id = _duel(0);
        uint64 bell = arena.tStart(id, 1);
        uint64 at = uint64(bound(offset, block.timestamp, uint256(bell) + 100));
        vm.warp(at);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes memory sig = _sig(id, 1, ca, aMove);
        if (at >= bell) vm.expectRevert(DuelArena.TooLate.selector);
        arena.anchorOwn(id, 1, 0, ca, sig);
    }

    function testFuzz_randomSignatureRejected(uint256 pk) public {
        pk = bound(pk, 1, 1e30);
        vm.assume(pk != aMove);
        uint256 id = _duel(0);
        vm.warp(arena.tStart(id, 1) - 1);
        bytes32 ca = _hash(id, 1, a, UP, 0, false);
        bytes memory sig = _sig(id, 1, ca, pk);
        vm.expectRevert(DuelArena.BadCommitSignature.selector);
        arena.anchorOwn(id, 1, 0, ca, sig);
    }

    function testFuzz_stakeIsConserved(uint96 stake, int32 bump, uint8 ma, uint8 mb) public {
        stake = uint96(bound(stake, 0, arena.UNVERIFIED_STAKE_CAP()));
        ma = ma % 4;
        mb = mb % 4;
        uint256 total = usdc.balanceOf(a) + usdc.balanceOf(b);
        uint256 id = _duel(stake);
        for (uint8 r = 1; r <= 6; ++r) _play(id, r, ma, mb);
        int64 move = int64(bound(int256(bump), -int256(P0) / 100, int256(P0) / 100));
        _settle(id, _updates(id, _bumps(6, move)));
        assertEq(usdc.balanceOf(address(arena)), 0);
        assertEq(usdc.balanceOf(a) + usdc.balanceOf(b) + usdc.balanceOf(rake), total);
    }

    function testFuzz_settleMatchesFightMath(int32 b1, int32 b2, int32 b3, uint8 ma, uint8 mb) public {
        ma = ma % 4;
        mb = mb % 4;
        uint256 id = _duel(0);
        for (uint8 r = 1; r <= 6; ++r) _play(id, r, ma, mb);
        int64[] memory bumps = new int64[](6);
        int256 lim = int256(P0) / 200;
        bumps[0] = int64(bound(int256(b1), -lim, lim));
        bumps[1] = int64(bound(int256(b2), -lim, lim));
        bumps[2] = int64(bound(int256(b3), -lim, lim));
        F.MatchRound[] memory rs = new F.MatchRound[](6);
        int64 p = P0;
        for (uint256 i; i < 6; ++i) {
            rs[i].p0 = p;
            p += bumps[i];
            rs[i].p1 = p;
            rs[i].a = F.Command(ma, 0, false);
            rs[i].b = F.Command(mb, 0, false);
        }
        F.MatchState memory want = F.resolveMatch(_rules(vm.readFile("../config/params.json")), int256(uint256(SIGMA)), 486e15, rs);
        vm.expectEmit(true, false, false, false);
        emit DuelArena.DuelSettled(id, want.winner, want.reason, want.r, 0, 0);
        _settle(id, _updates(id, bumps));
    }

    function testFuzz_voidTiming(uint64 offset) public {
        uint256 id = _duel(0);
        bytes memory proof = _stale(id, 1);
        uint64 deadline = arena.settleDeadline(id);
        uint64 at = uint64(bound(offset, uint256(deadline) - 100, uint256(deadline) + 100));
        vm.warp(at);
        if (at <= deadline) vm.expectRevert(DuelArena.TooEarly.selector);
        arena.voidBoundary{value: 1 ether}(id, 1, proof);
    }
}
