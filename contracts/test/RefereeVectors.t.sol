// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib as M} from "solady/utils/FixedPointMathLib.sol";
import {Referee} from "../src/Referee.sol";
import {IReferee} from "../src/interfaces/IReferee.sol";
import {ConfigReader} from "./helpers/ConfigReader.sol";
import {MockFamily} from "./helpers/MockFamily.sol";

/// @notice Replays shared/vectors: Solidity must match the Python reference bit for bit.
contract VectorsTest is Test {
    MockFamily family;
    string flat;
    bytes32[] ids;

    function setUp() public {
        flat = vm.readFile("../shared/vectors/referee-flat.json");
        family = new MockFamily();
    }

    function _referee() internal returns (Referee) {
        string memory j = ConfigReader.params();
        (bytes32[] memory feeds, uint256[] memory sigmas) = ConfigReader.feeds(j);
        ids = feeds;
        return new Referee(address(this), family, ConfigReader.refereeParams(j), feeds, sigmas);
    }

    function test_lnWad_cases() public view {
        int256[] memory x = vm.parseJsonIntArray(flat, ".lnX");
        int256[] memory y = vm.parseJsonIntArray(flat, ".lnY");
        for (uint256 i; i < x.length; ++i) assertEq(M.lnWad(x[i]), y[i]);
    }

    function test_bars() public {
        Referee r = _referee();
        uint256[] memory k = vm.parseJsonUintArray(flat, ".barK");
        int256[] memory y = vm.parseJsonIntArray(flat, ".barY");
        for (uint256 i; i < k.length; ++i) assertEq(r.lnBar(k[i]), y[i]);
    }

    function _addr(int256 who) internal pure returns (address) {
        return address(uint160(uint256(who) + 1000));
    }

    function _check(Referee r, address f, int256[] memory v, uint256 at) internal view {
        Referee.FighterView memory s = r.fighterState(f);
        for (uint256 m; m < 4; ++m) {
            assertEq(int256(uint256(s.n[m])), v[at + m], "n");
            assertEq(int256(uint256(s.nShort[m])), v[at + 4 + m], "nShort");
        }
        assertEq(s.logW, v[at + 8], "logW");
        assertEq(int256(s.lambda), v[at + 9], "lambda");
        if (v[at + 10] != 0) assertEq(int256(s.A), v[at + 10], "A");
        assertEq(s.logL, v[at + 11], "logL");
        assertEq(int256(uint256(s.rounds)), v[at + 12], "rounds");
        assertEq(int256(s.kAtCert), v[at + 13], "kAtCert");
        assertEq(s.lapsed ? int256(1) : int256(0), v[at + 14], "lapsed");
    }

    function test_histories() public {
        uint256 count = vm.parseJsonUint(flat, ".count");
        uint256 width = vm.parseJsonUint(flat, ".width");
        uint256 steps;
        for (uint256 h; h < count; ++h) {
            Referee r = _referee();
            int256[] memory v = vm.parseJsonIntArray(flat, string.concat(".h[", vm.toString(h), "]"));
            for (uint256 at; at < v.length; at += width) {
                address a = _addr(v[at + 6]);
                family.set(a, uint256(v[at + 8]));
                if (v[at] == 1) {
                    address b = _addr(v[at + 9]);
                    family.set(b, uint256(v[at + 11]));
                    r.recordRound(
                        ids[uint256(v[at + 1])], uint64(uint256(v[at + 2])), v[at + 3], v[at + 4], v[at + 5],
                        a, uint8(uint256(v[at + 7])), b, uint8(uint256(v[at + 10]))
                    );
                    Referee.FeedView memory f = r.feedState(ids[uint256(v[at + 1])]);
                    uint256 fa = at + 42;
                    assertEq(f.meanZ, v[fa], "meanZ");
                    assertEq(f.meanAbs, v[fa + 1], "meanAbs");
                    assertEq(f.meanZShort, v[fa + 2], "meanZShort");
                    assertEq(f.meanAbsShort, v[fa + 3], "meanAbsShort");
                    assertEq(int256(f.varReturn), v[fa + 4], "varReturn");
                    assertEq(int256(uint256(f.count)), v[fa + 5], "count");
                } else {
                    r.recordForfeit(a);
                }
                _check(r, _addr(1), v, at + 12);
                _check(r, _addr(2), v, at + 27);
                ++steps;
            }
        }
        assertGe(count, 12);
        assertGe(steps, 80);
    }
}
