// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Referee} from "../src/Referee.sol";
import {IReferee} from "../src/interfaces/IReferee.sol";
import {ConfigReader} from "./helpers/ConfigReader.sol";
import {MockFamily} from "./helpers/MockFamily.sol";

contract RefereeTest is Test {
    uint8 constant UP = 0;
    uint8 constant DOWN = 1;
    uint8 constant GUARD = 2;
    int256 constant P0 = 10_000_000_000;

    MockFamily family;
    Referee ref;
    IReferee.Params p;
    bytes32 feed;
    uint256 sigmaInit;
    address a = address(0xA);
    address b = address(0xB);
    address c = address(0xC);
    uint64 t = 1_800_000_000;

    function setUp() public {
        string memory j = ConfigReader.params();
        (bytes32[] memory feeds, uint256[] memory sigmas) = ConfigReader.feeds(j);
        feed = feeds[0];
        sigmaInit = sigmas[0];
        p = ConfigReader.refereeParams(j);
        family = new MockFamily();
        ref = new Referee(address(this), family, p, feeds, sigmas);
        family.set(a, 2);
        family.set(b, 2);
        family.set(c, 2);
    }

    function _round(address x, uint8 mx, address y, uint8 my, int256 p1) internal {
        ref.recordRound(feed, t, P0, p1, 486e15, x, mx, y, my);
        t += p.tapeS;
    }

    /// @dev Plays until `who` certifies, always guessing the direction right.
    function _certify(address who) internal {
        for (uint256 i; i < 2000; ++i) {
            bool up = i % 2 == 0;
            int256 p1 = up ? P0 + P0 / 2000 : P0 - P0 / 2000;
            _round(who, up ? UP : DOWN, b, GUARD, p1);
            if (ref.verdictOf(who).skilled) return;
        }
        revert("never certified");
    }

    function test_onlyArenaCanWrite() public {
        vm.startPrank(a);
        vm.expectRevert(IReferee.NotArena.selector);
        ref.recordForfeit(a);
        vm.expectRevert(IReferee.NotArena.selector);
        ref.recordRound(feed, t, P0, P0, 486e15, a, UP, b, UP);
        vm.stopPrank();
    }

    function test_unknownFeedReverts() public {
        vm.expectRevert(IReferee.UnknownFeed.selector);
        ref.recordRound(bytes32(uint256(1)), t, P0, P0, 486e15, a, UP, b, UP);
    }

    function test_moveAboveThreeReverts() public {
        vm.expectRevert(IReferee.BadMove.selector);
        ref.recordRound(feed, t, P0, P0, 486e15, a, 4, b, UP);
    }

    function test_forfeitIsTheWorstRound() public {
        _certify(a);
        IReferee.Verdict memory before = ref.verdictOf(c);
        for (uint256 i; i < 30; ++i) _round(c, i % 2 == 0 ? UP : DOWN, b, GUARD, i % 2 == 0 ? P0 + P0 / 2000 : P0 - P0 / 2000);
        before = ref.verdictOf(c);
        assertGt(before.lambda, 0);
        ref.recordForfeit(c);
        IReferee.Verdict memory afterwards = ref.verdictOf(c);
        assertLt(afterwards.logW, before.logW);
        assertEq(afterwards.rounds, before.rounds + 1);
    }

    function test_opponentDoesNotChangeAFightersState() public {
        Referee other = new Referee(address(this), family, p, _ids(), _sigmas());
        for (uint256 i; i < 40; ++i) {
            int256 p1 = i % 3 == 0 ? P0 + P0 / 4000 : P0 - P0 / 5000;
            ref.recordRound(feed, t, P0, p1, 486e15, a, GUARD, b, UP);
            other.recordRound(feed, t, P0, p1, 486e15, a, GUARD, c, 3);
            t += p.tapeS;
        }
        assertEq(keccak256(abi.encode(ref.fighterState(a))), keccak256(abi.encode(other.fighterState(a))));
    }

    function _ids() internal view returns (bytes32[] memory ids) {
        ids = new bytes32[](1);
        ids[0] = feed;
    }

    function _sigmas() internal view returns (uint256[] memory s) {
        s = new uint256[](1);
        s[0] = sigmaInit;
    }

    function test_feedUpdatesOncePerTape() public {
        ref.recordRound(feed, t, P0, P0 + P0 / 1000, 486e15, a, UP, b, DOWN);
        Referee.FeedView memory once = ref.feedState(feed);
        ref.recordRound(feed, t + p.tapeS - 1, P0, P0 + P0 / 1000, 486e15, c, UP, b, DOWN);
        assertEq(keccak256(abi.encode(ref.feedState(feed))), keccak256(abi.encode(once)));
        ref.recordRound(feed, t + p.tapeS, P0, P0 + P0 / 1000, 486e15, c, UP, b, DOWN);
        assertEq(ref.feedState(feed).count, once.count + 1);
    }

    function test_siblingRaisesBarImmediately() public {
        int256 before = ref.verdictOf(a).lnBar;
        family.set(a, 3);
        assertGt(ref.verdictOf(a).lnBar, before);
    }

    function test_certifiedKeepsKAtCertWhenFamilyGrows() public {
        _certify(a);
        IReferee.Verdict memory v = ref.verdictOf(a);
        assertTrue(v.skilled);
        assertEq(v.kAtCert, 2);
        family.set(a, 9);
        v = ref.verdictOf(a);
        assertTrue(v.skilled);
        assertEq(v.kAtCert, 2);
        assertEq(v.lnBar, ref.lnBar(9));
    }

    function test_lapseFlipsAfterEdgeTurnsNegative() public {
        _certify(a);
        for (uint256 i; i < 20_000 && !ref.verdictOf(a).lapsed; ++i) {
            bool up = i % 2 == 0;
            _round(a, up ? DOWN : UP, b, GUARD, up ? P0 + P0 / 2000 : P0 - P0 / 2000);
        }
        IReferee.Verdict memory v = ref.verdictOf(a);
        assertTrue(v.lapsed);
        assertTrue(v.skilled);
    }

    function test_rankListsCertifiedFightersBestFirstAndDropsLapsed() public {
        assertEq(ref.topFighter(feed, 1), address(0));
        _certify(a);
        assertEq(ref.topFighter(feed, 1), a);
        _certify(c);
        assertTrue(ref.topFighter(feed, 1) == a || ref.topFighter(feed, 1) == c);
        assertTrue(ref.topFighter(feed, 2) != address(0));
        assertEq(ref.topFighter(feed, 3), address(0));
        for (uint256 i; i < 20_000 && !ref.verdictOf(a).lapsed; ++i) {
            bool up = i % 2 == 0;
            _round(a, up ? DOWN : UP, b, GUARD, up ? P0 + P0 / 2000 : P0 - P0 / 2000);
        }
        assertEq(ref.topFighter(feed, 1), c);
        assertEq(ref.topFighter(feed, 2), address(0));
    }

    function testFuzz_recordNeverReverts(int64 p1, uint8 ma, uint8 mb, uint8 rounds) public {
        vm.assume(p1 > 0);
        ma = ma % 4;
        mb = mb % 4;
        for (uint256 i; i < uint256(rounds) % 20 + 1; ++i) {
            _round(a, ma, b, mb, int256(p1));
            ref.recordForfeit(a);
        }
    }

    function test_constructorRejectsBadParams() public {
        IReferee.Params memory bad = p;
        bad.lambdaMax = 6e17;
        vm.expectRevert(IReferee.BadParams.selector);
        new Referee(address(this), family, bad, _ids(), _sigmas());
    }
}
