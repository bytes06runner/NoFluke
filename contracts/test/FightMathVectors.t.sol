// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FightMath as F} from "../src/FightMath.sol";

/// @dev External wrapper, so a test can catch the library's reverts.
contract FightMathHarness {
    function match_(F.Rules memory rules, int256 sigma, int256 c, F.MatchRound[] memory rounds)
        external
        pure
        returns (F.MatchState memory)
    {
        return F.resolveMatch(rules, sigma, c, rounds);
    }
}

/// @notice Replays shared/vectors/fightmath.json: Solidity must match the Python reference bit for bit.
contract VectorsFightMathTest is Test {
    string v;
    F.Rules R;
    FightMathHarness h;

    function setUp() public {
        v = vm.readFile("../shared/vectors/fightmath.json");
        string memory j = vm.readFile("../config/params.json");
        R = F.Rules({
            hpStart: vm.parseJsonInt(j, ".match.hpStart"),
            meterStart: vm.parseJsonInt(j, ".match.meterStart"),
            meterCap: vm.parseJsonInt(j, ".match.meterCap"),
            overdriveCost: vm.parseJsonInt(j, ".match.overdriveCost"),
            meterWin: vm.parseJsonInt(j, ".match.meterWin"),
            meterLoss: vm.parseJsonInt(j, ".match.meterLoss"),
            damageBase: vm.parseJsonInt(j, ".match.damageBase"),
            diffCap: vm.parseJsonInt(j, ".match.damageDiffCapPoints") * F.WAD,
            tie: vm.parseJsonInt(j, ".match.tiePoints") * F.WAD,
            regularRounds: uint8(vm.parseJsonUint(j, ".match.regularRounds")),
            maxRounds: uint8(vm.parseJsonUint(j, ".match.maxRounds")),
            sigmaMin: vm.parseJsonInt(j, ".match.sigmaMinPpm"),
            sigmaMax: vm.parseJsonInt(j, ".match.sigmaMaxPpm"),
            payoffPerZ: vm.parseJsonInt(j, ".match.payoffPerZ"),
            counterNum: vm.parseJsonInt(j, ".match.counterHitNumerator"),
            counterDen: vm.parseJsonInt(j, ".match.counterHitDenominator")
        });
        h = new FightMathHarness();
    }

    function _u8(int256 x) internal pure returns (uint8) {
        return uint8(uint256(x));
    }

    function test_rounds() public view {
        int256[] memory f = vm.parseJsonIntArray(v, ".rounds");
        uint256 w = vm.parseJsonUint(v, ".roundWidth");
        for (uint256 at; at < f.length; at += w) _checkRound(f, at);
    }

    function _checkRound(int256[] memory f, uint256 at) internal view {
        F.Fighter memory a = F.Fighter(f[at + 4], f[at + 5]);
        F.Fighter memory b = F.Fighter(f[at + 6], f[at + 7]);
        F.Command memory ca = F.Command(_u8(f[at + 8]), _u8(f[at + 9]), f[at + 10] == 1);
        F.Command memory cb = F.Command(_u8(f[at + 11]), _u8(f[at + 12]), f[at + 13] == 1);
        F.RoundResult memory r = F.resolveRound(R, a, b, ca, cb, F.zWad(f[at], f[at + 1], f[at + 2]), f[at + 3], f[at + 14] == 1);
        assertEq(r.z, f[at + 15], "z");
        assertEq(r.damage, f[at + 16], "damage");
        assertEq(int256(uint256(r.loser)), f[at + 17], "loser");
        assertEq(r.a.pay, f[at + 18], "payA");
        assertEq(r.a.od, f[at + 19] == 1, "odA");
        assertEq(r.a.counter, f[at + 20] == 1, "counterA");
        assertEq(r.b.pay, f[at + 21], "payB");
        assertEq(r.b.od, f[at + 22] == 1, "odB");
        assertEq(r.b.counter, f[at + 23] == 1, "counterB");
        assertEq(a.hp, f[at + 24], "hpA");
        assertEq(a.meter, f[at + 25], "meterA");
        assertEq(b.hp, f[at + 26], "hpB");
        assertEq(b.meter, f[at + 27], "meterB");
    }

    function _rounds(int256[] memory x) internal pure returns (F.MatchRound[] memory rs, uint256 next) {
        uint256 n = uint256(x[2]);
        rs = new F.MatchRound[](n);
        uint256 i = 3;
        for (uint256 r; r < n; ++r) {
            rs[r] = F.MatchRound({
                p0: x[i],
                p1: x[i + 1],
                voided: x[i + 2] == 1,
                aMissing: x[i + 3] == 1,
                bMissing: x[i + 4] == 1,
                a: F.Command(_u8(x[i + 5]), _u8(x[i + 6]), x[i + 7] == 1),
                b: F.Command(_u8(x[i + 8]), _u8(x[i + 9]), x[i + 10] == 1)
            });
            i += 11;
        }
        next = i;
    }

    function test_matches() public view {
        uint256 count = vm.parseJsonUint(v, ".matchCount");
        for (uint256 c; c < count; ++c) {
            int256[] memory x = vm.parseJsonIntArray(v, string.concat(".matches[", vm.toString(c), "]"));
            (F.MatchRound[] memory rs, uint256 at) = _rounds(x);
            F.MatchState memory m = F.resolveMatch(R, x[0], x[1], rs);
            assertEq(int256(uint256(m.winner)), x[at], "winner");
            assertEq(int256(uint256(m.reason)), x[at + 1], "reason");
            assertEq(int256(uint256(m.r)), x[at + 2], "rounds");
            assertEq(m.a.hp, x[at + 3], "hpA");
            assertEq(m.a.meter, x[at + 4], "meterA");
            assertEq(m.b.hp, x[at + 5], "hpB");
            assertEq(m.b.meter, x[at + 6], "meterB");
        }
    }

    function test_rejects() public {
        uint256 count = vm.parseJsonUint(v, ".rejectCount");
        for (uint256 c; c < count; ++c) {
            int256[] memory x = vm.parseJsonIntArray(v, string.concat(".rejects[", vm.toString(c), "]"));
            (F.MatchRound[] memory rs, uint256 at) = _rounds(x);
            bytes4 want = x[at] == 1 ? F.SigmaBounds.selector : x[at] == 2 ? F.BadPrice.selector : F.Truncated.selector;
            vm.expectRevert(want);
            h.match_(R, x[0], x[1], rs);
        }
    }

    function test_voids() public view {
        uint256 count = vm.parseJsonUint(v, ".voidCount");
        for (uint256 c; c < count; ++c) {
            int256[] memory x = vm.parseJsonIntArray(v, string.concat(".voids[", vm.toString(c), "]"));
            assertEq(F.isVoid(x[0], x[1], x[2], x[3], x[4], x[5], x[6]), x[7] == 1);
        }
    }

    function testFuzz_damageBoundedAndHpNeverNegative(int64 z, uint8 m1, uint8 m2, bool od) public view {
        F.Fighter memory a = F.Fighter(R.hpStart, R.meterCap);
        F.Fighter memory b = F.Fighter(R.hpStart, R.meterCap);
        F.RoundResult memory r = F.resolveRound(R, a, b, F.Command(m1 % 4, 0, od), F.Command(m2 % 4, 1, od), int256(z) * 1e6, 486e15, false);
        assertLe(r.damage, R.damageBase + (2 * R.diffCap) / F.WAD);
        assertGe(a.hp, 0);
        assertGe(b.hp, 0);
    }
}
