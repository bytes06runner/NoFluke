// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPointMathLib as M} from "solady/utils/FixedPointMathLib.sol";
import {IFamilySize, IReferee} from "./interfaces/IReferee.sol";

/// @title Luck referee v3
/// @notice Tests whether a fighter's moves know something about the market that their habits alone do not.
///         Verdicts are computed here from settled rounds, so nobody posts them. No owner, no setters.
/// @dev Must match engine/nofluke/referee.py and shared/src/referee.ts bit for bit (make vectors).
///      See docs/scoring-rule.md for the maths and why it is valid.
contract Referee is IReferee {
    int256 private constant WAD = 1e18;
    uint256 private constant MOVES = 4;
    uint256 private constant PPM_TO_WAD = 1e12;

    struct Fighter {
        uint128[4] n;
        uint128[4] nShort;
        int128 logW;
        int128 logL;
        uint128 A;
        uint64 lambda;
        uint32 rounds;
        uint24 kAtCert;
        bool lapsed;
    }

    struct Feed {
        int128 meanZ;
        int128 meanAbs;
        int128 meanZShort;
        int128 meanAbsShort;
        uint256 varReturn;
        uint64 count;
        bool known;
    }

    struct FighterView {
        uint128[4] n;
        uint128[4] nShort;
        int256 logW;
        uint256 lambda;
        uint256 A;
        int256 logL;
        uint32 rounds;
        uint256 kAtCert;
        bool lapsed;
    }

    struct FeedView {
        int256 meanZ;
        int256 meanAbs;
        int256 meanZShort;
        int256 meanAbsShort;
        uint256 varReturn;
        uint64 count;
    }

    /// @dev One round's inputs. Both fighters read the feed state from before the round.
    struct RoundCtx {
        bytes32 feedId;
        int256 r;
        int256 z;
        int256 c;
        Feed before;
    }

    address public immutable arena;
    IFamilySize public immutable family;

    uint256 public immutable ALPHA_INV;
    int256 public immutable Z_CLIP;
    int256 public immutable DELTA;
    int256 public immutable PAYOFF_PER_Z;
    int256 public immutable GAMMA;
    int256 public immutable GAMMA_SHORT;
    uint256 public immutable MEAN_HORIZON;
    uint256 public immutable MEAN_SHORT_HORIZON;
    int256 public immutable SIGMA_HORIZON;
    int256 public immutable KAPPA;
    int256 public immutable M_POINTS;
    int256 public immutable LAMBDA_MAX;
    int256 public immutable ONS_BETA;
    uint128 public immutable ONS_A0;
    int256 public immutable LAPSE_LAMBDA;
    int256 public immutable LN_LAPSE_A;
    int256 public immutable LAPSE_EDGE_FLOOR;
    uint256 public immutable SIGMA_FLOOR;
    uint64 public immutable TAPE_S;
    uint256 public immutable RANK_DEPTH;

    mapping(address => Fighter) private _fighters;
    mapping(bytes32 => Feed) private _feeds;
    mapping(bytes32 => address[]) private _ranked;
    mapping(bytes32 => mapping(uint256 => bool)) private _tapeSeen;

    modifier onlyArena() {
        if (msg.sender != arena) revert NotArena();
        _;
    }

    constructor(address arena_, IFamilySize family_, Params memory p, bytes32[] memory feedIds, uint256[] memory sigmaInitPpm) {
        // Bounds that a config mistake could otherwise silently remove.
        if (
            arena_ == address(0) || address(family_) == address(0) || p.alphaInv == 0 || p.habitHorizon < 2
                || p.habitShortHorizon < 2 || p.habitShortHorizon >= p.habitHorizon || p.meanHorizon == 0
                || p.meanShortHorizon == 0 || p.meanShortHorizon >= p.meanHorizon || p.sigmaHorizon == 0 || p.m <= 0
                || p.zClip <= 0 || p.delta <= 0 || p.lambdaMax >= uint256(WAD) || p.lapseLambda >= uint256(WAD) / 2
                || p.lapseA < 2 || p.onsA0 == 0 || p.tapeS == 0 || p.rankDepth == 0 || p.sigmaMinPpm == 0
                || feedIds.length != sigmaInitPpm.length
        ) revert BadParams();
        arena = arena_;
        family = family_;
        ALPHA_INV = p.alphaInv;
        Z_CLIP = p.zClip;
        DELTA = p.delta;
        PAYOFF_PER_Z = p.payoffPerZ;
        GAMMA = WAD - WAD / int256(p.habitHorizon);
        GAMMA_SHORT = WAD - WAD / int256(p.habitShortHorizon);
        MEAN_HORIZON = p.meanHorizon;
        MEAN_SHORT_HORIZON = p.meanShortHorizon;
        SIGMA_HORIZON = int256(p.sigmaHorizon);
        KAPPA = int256(p.kappa);
        M_POINTS = p.m;
        LAMBDA_MAX = int256(p.lambdaMax);
        ONS_BETA = int256(p.onsBeta);
        ONS_A0 = uint128(p.onsA0);
        LAPSE_LAMBDA = int256(p.lapseLambda);
        LN_LAPSE_A = M.lnWad(int256(p.lapseA) * WAD);
        LAPSE_EDGE_FLOOR = p.lapseEdgeFloor;
        SIGMA_FLOOR = p.sigmaMinPpm * PPM_TO_WAD;
        TAPE_S = p.tapeS;
        RANK_DEPTH = p.rankDepth;
        for (uint256 i; i < feedIds.length; ++i) {
            uint256 sigma = sigmaInitPpm[i] * PPM_TO_WAD;
            _feeds[feedIds[i]].varReturn = (sigma * sigma) / uint256(WAD);
            _feeds[feedIds[i]].known = true;
        }
    }

    /// @inheritdoc IReferee
    function recordRound(
        bytes32 feedId,
        uint64 tStart,
        int256 p0,
        int256 p1,
        int256 c,
        address fighterA,
        uint8 moveA,
        address fighterB,
        uint8 moveB
    ) external onlyArena {
        if (!_feeds[feedId].known) revert UnknownFeed();
        if (moveA >= MOVES || moveB >= MOVES) revert BadMove();
        RoundCtx memory ctx = _context(feedId, p0, p1, c);
        _update(fighterA, moveA, ctx);
        _update(fighterB, moveB, ctx);
        _updateFeed(feedId, tStart, ctx.r, ctx.z);
    }

    /// @inheritdoc IReferee
    function recordForfeit(address fighter) external onlyArena {
        Fighter storage s = _fighters[fighter];
        _ensureInit(s);
        _bet(s, fighter, -WAD, bytes32(0));
    }

    /// @inheritdoc IReferee
    function verdictOf(address fighter) external view returns (Verdict memory v) {
        Fighter storage s = _fighters[fighter];
        v = Verdict({
            skilled: s.kAtCert > 0,
            lapsed: s.lapsed,
            logW: s.logW,
            lnBar: lnBar(family.familySize(fighter)),
            rounds: s.rounds,
            lambda: s.lambda,
            kAtCert: s.kAtCert
        });
    }

    /// @inheritdoc IReferee
    function topFighter(bytes32 feedId, uint256 rank) external view returns (address) {
        address[] storage list = _ranked[feedId];
        if (rank == 0 || rank > list.length) return address(0);
        return list[rank - 1];
    }

    /// @notice ln(K(K+1)/α), the evidence a family of K must reach.
    function lnBar(uint256 k) public view returns (int256) {
        return M.lnWad(int256(k * (k + 1) * ALPHA_INV) * WAD);
    }

    function fighterState(address fighter) external view returns (FighterView memory) {
        Fighter storage s = _fighters[fighter];
        return FighterView(s.n, s.nShort, s.logW, s.lambda, s.A == 0 ? uint256(ONS_A0) : s.A, s.logL, s.rounds, s.kAtCert, s.lapsed);
    }

    function feedState(bytes32 feedId) external view returns (FeedView memory) {
        Feed storage f = _feeds[feedId];
        return FeedView(f.meanZ, f.meanAbs, f.meanZShort, f.meanAbsShort, f.varReturn, f.count);
    }

    function _context(bytes32 feedId, int256 p0, int256 p1, int256 c) private view returns (RoundCtx memory ctx) {
        Feed storage f = _feeds[feedId];
        ctx.feedId = feedId;
        ctx.r = ((p1 - p0) * WAD) / p0;
        ctx.z = (ctx.r * WAD) / int256(_sigma(f));
        ctx.c = c;
        ctx.before = f;
    }

    function _sigma(Feed storage f) private view returns (uint256) {
        uint256 s = M.sqrt(f.varReturn * uint256(WAD));
        return s > SIGMA_FLOOR ? s : SIGMA_FLOOR;
    }

    function _ensureInit(Fighter storage s) private {
        if (s.A == 0) s.A = ONS_A0;
    }

    function _clip(int256 x, int256 lo, int256 hi) private pure returns (int256) {
        return x < lo ? lo : x > hi ? hi : x;
    }

    function _abs(int256 x) private pure returns (int256) {
        return x < 0 ? -x : x;
    }

    function _means(int256 meanZ, int256 meanAbs, int256 c) private view returns (int256[4] memory mu) {
        int256 k = PAYOFF_PER_Z;
        int256 d = DELTA;
        mu[0] = _clip(k * meanZ, -d, d);
        mu[1] = _clip(-k * meanZ, -d, d);
        mu[2] = _clip(k * (c - meanAbs), -d, d);
        mu[3] = _clip(k * (meanAbs - c), -d, d);
    }

    function _driftD(Fighter storage s) private view returns (int256 total) {
        int256 nl;
        int256 ns;
        for (uint256 m; m < MOVES; ++m) {
            nl += int256(uint256(s.n[m]));
            ns += int256(uint256(s.nShort[m]));
        }
        for (uint256 m; m < MOVES; ++m) {
            int256 fl = ((int256(uint256(s.n[m])) + WAD) * WAD) / (nl + 4 * WAD);
            int256 fs = ((int256(uint256(s.nShort[m])) + WAD) * WAD) / (ns + 4 * WAD);
            total += _abs(fs - fl);
        }
    }

    function _centred(int256 zc, int256 c, int256[4] memory mu) private view returns (int256[4] memory) {
        int256 a = _abs(zc);
        int256 k = PAYOFF_PER_Z;
        return [k * zc - mu[0], -k * zc - mu[1], k * (c - a) - mu[2], k * (a - c) - mu[3]];
    }

    function _baseline(Fighter storage s, int256[4] memory centred) private view returns (int256) {
        int256 sum;
        int256 total;
        for (uint256 m; m < MOVES; ++m) {
            int256 nm = int256(uint256(s.n[m]));
            sum += (nm + WAD) * centred[m];
            total += nm;
        }
        return sum / (total + 4 * WAD);
    }

    function _driftE(int256[4] memory lng, int256[4] memory sht) private pure returns (int256 e) {
        for (uint256 m; m < MOVES; ++m) {
            int256 gap = _abs(sht[m] - lng[m]);
            if (gap > e) e = gap;
        }
    }

    function _excessV(Fighter storage s, Feed memory f, uint8 move, int256 z, int256 c) private view returns (int256) {
        int256[4] memory mu = _means(f.meanZ, f.meanAbs, c);
        int256[4] memory sht = _means(f.meanZShort, f.meanAbsShort, c);
        int256[4] memory centred = _centred(_clip(z, -Z_CLIP, Z_CLIP), c, mu);
        int256 penalty = (((KAPPA * _driftD(s)) / WAD) * _driftE(mu, sht)) / WAD;
        int256 x = centred[move] - _baseline(s, centred) - penalty;
        return _clip((x * WAD) / M_POINTS, -WAD, WAD);
    }

    function _bet(Fighter storage s, address fighter, int256 v, bytes32 feedId) private {
        int256 lambda = int256(uint256(s.lambda));
        int256 term = WAD + (lambda * v) / WAD;
        int256 logW = int256(s.logW) + M.lnWad(term);
        int256 g = (v * WAD) / term;
        int256 A = int256(uint256(s.A)) + (g * g) / WAD;
        lambda = _clip(lambda + (((ONS_BETA * g) / WAD) * WAD) / A, 0, LAMBDA_MAX);
        uint32 rounds = s.rounds + 1;
        s.logW = int128(logW);
        s.A = uint128(uint256(A));
        s.lambda = uint64(uint256(lambda));
        s.rounds = rounds;
        uint256 k = family.familySize(fighter);
        if (s.kAtCert == 0) {
            if (logW >= lnBar(k)) {
                s.kAtCert = uint24(k);
                emit Certified(fighter, k, logW);
            }
        } else if (!s.lapsed) {
            int256 prev = int256(s.logL);
            if (prev < 0) prev = 0;
            int256 logL = prev + M.lnWad(WAD - (LAPSE_LAMBDA * (v - LAPSE_EDGE_FLOOR)) / WAD);
            s.logL = int128(logL);
            if (logL >= LN_LAPSE_A) {
                s.lapsed = true;
                emit Lapsed(fighter);
            }
        }
        emit Rated(fighter, feedId, v, logW, uint256(lambda), rounds);
    }

    function _update(address fighter, uint8 move, RoundCtx memory ctx) private {
        Fighter storage s = _fighters[fighter];
        _ensureInit(s);
        _bet(s, fighter, _excessV(s, ctx.before, move, ctx.z, ctx.c), ctx.feedId);
        for (uint256 m; m < MOVES; ++m) {
            uint256 hit = m == move ? uint256(WAD) : 0;
            s.n[m] = uint128((uint256(s.n[m]) * uint256(GAMMA)) / uint256(WAD) + hit);
            s.nShort[m] = uint128((uint256(s.nShort[m]) * uint256(GAMMA_SHORT)) / uint256(WAD) + hit);
        }
        if (s.kAtCert > 0) _rerank(ctx.feedId, fighter, s);
    }

    function _updateFeed(bytes32 feedId, uint64 t, int256 r, int256 z) private {
        // Exactly once per tape, in any settlement order: a rated round's tape always reaches the feed.
        uint256 tape = t / TAPE_S;
        if (_tapeSeen[feedId][tape]) return;
        _tapeSeen[feedId][tape] = true;
        Feed storage f = _feeds[feedId];
        int256 zc = _clip(z, -Z_CLIP, Z_CLIP);
        int256 a = _abs(zc);
        uint64 count = f.count + 1;
        int256 longH = int256(M.min(count, MEAN_HORIZON));
        int256 shortH = int256(M.min(count, MEAN_SHORT_HORIZON));
        f.meanZ += int128((zc - f.meanZ) / longH);
        f.meanAbs += int128((a - f.meanAbs) / longH);
        f.meanZShort += int128((zc - f.meanZShort) / shortH);
        f.meanAbsShort += int128((a - f.meanAbsShort) / shortH);
        int256 var_ = int256(f.varReturn);
        f.varReturn = uint256(var_ + ((r * r) / WAD - var_) / SIGMA_HORIZON);
        f.count = count;
    }

    function _gap(address fighter) private view returns (int256) {
        return int256(_fighters[fighter].logW) - lnBar(family.familySize(fighter));
    }

    /// @dev Keeps a short list per feed, best evidence above its bar first. A lapsed fighter leaves the list.
    function _rerank(bytes32 feedId, address fighter, Fighter storage s) private {
        address[] storage list = _ranked[feedId];
        uint256 len = list.length;
        for (uint256 i; i < len; ++i) {
            if (list[i] == fighter) {
                for (uint256 j = i; j + 1 < len; ++j) list[j] = list[j + 1];
                list.pop();
                --len;
                break;
            }
        }
        if (s.lapsed) return;
        int256 gap = _gap(fighter);
        uint256 at = len;
        for (uint256 i; i < len; ++i) {
            if (gap > _gap(list[i])) {
                at = i;
                break;
            }
        }
        if (at >= RANK_DEPTH) return;
        list.push(fighter);
        for (uint256 j = len; j > at; --j) list[j] = list[j - 1];
        list[at] = fighter;
        if (list.length > RANK_DEPTH) list.pop();
    }
}
