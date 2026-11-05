// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Match rules
/// @notice Pure integer rules for a duel. Must match engine/nofluke/fightmath.py and shared/src/fightmath.ts bit for bit.
library FightMath {
    int256 internal constant WAD = 1e18;
    int256 private constant PPM_SCALE = 1e24; // WAD * 1e6, because sigma is in parts per million
    int256 private constant BPS = 10_000;

    uint8 internal constant REASON_KO = 0;
    uint8 internal constant REASON_HP = 1;
    uint8 internal constant REASON_FORFEIT = 2;
    uint8 internal constant REASON_DRAW = 3;

    error SigmaBounds();
    error BadPrice();
    error Truncated();

    struct Rules {
        int256 hpStart;
        int256 meterStart;
        int256 meterCap;
        int256 overdriveCost;
        int256 meterWin;
        int256 meterLoss;
        int256 damageBase;
        int256 diffCap;
        int256 tie;
        uint8 regularRounds;
        uint8 maxRounds;
        int256 sigmaMin;
        int256 sigmaMax;
        int256 payoffPerZ;
        int256 counterNum;
        int256 counterDen;
    }

    struct Fighter {
        int256 hp;
        int256 meter;
    }

    struct Command {
        uint8 move;
        uint8 read;
        bool overdrive;
    }

    struct Side {
        int256 pay;
        bool od;
        bool counter;
    }

    struct RoundResult {
        int256 z;
        int256 damage;
        uint8 loser;
        Side a;
        Side b;
    }

    struct MatchRound {
        int256 p0;
        int256 p1;
        bool voided;
        bool aMissing;
        bool bMissing;
        Command a;
        Command b;
    }

    struct MatchState {
        Fighter a;
        Fighter b;
        uint8 r;
        bool done;
        uint8 winner;
        uint8 reason;
    }

    function moveType(uint8 move) internal pure returns (uint8) {
        return move <= 1 ? 0 : move - 1;
    }

    function validMove(uint8 move) internal pure returns (bool) {
        return move <= 3;
    }

    function validRead(uint8 read) internal pure returns (bool) {
        return read <= 2;
    }

    function zWad(int256 p0, int256 p1, int256 sigmaPpm) internal pure returns (int256) {
        if (p0 <= 0 || p1 <= 0) revert BadPrice();
        return ((p1 - p0) * PPM_SCALE) / (p0 * sigmaPpm);
    }

    function isVoid(int256 p0, int256 conf0, int256 expo0, int256 p1, int256 conf1, int256 expo1, int256 confCapBps)
        internal
        pure
        returns (bool)
    {
        if (p0 <= 0 || p1 <= 0 || expo0 != expo1) return true;
        if (confCapBps == 0) return false;
        return conf0 * BPS > confCapBps * p0 || conf1 * BPS > confCapBps * p1;
    }

    function _abs(int256 x) private pure returns (int256) {
        return x < 0 ? -x : x;
    }

    function _min(int256 a, int256 b) private pure returns (int256) {
        return a < b ? a : b;
    }

    function basePayoff(Rules memory rules, uint8 move, int256 z, int256 c) internal pure returns (int256) {
        int256 k = rules.payoffPerZ;
        if (move == 0) return k * z;
        if (move == 1) return -k * z;
        if (move == 2) return k * (c - _abs(z));
        return k * (_abs(z) - c);
    }

    function _side(Rules memory rules, Fighter memory me, Command memory cmd, Command memory opp, int256 z, int256 c)
        private
        pure
        returns (Side memory s)
    {
        s.od = cmd.overdrive && me.meter >= rules.overdriveCost;
        if (s.od) me.meter -= rules.overdriveCost;
        s.pay = basePayoff(rules, cmd.move, z, c);
        if (s.od) s.pay *= 2;
        s.counter = cmd.read == moveType(opp.move) && s.pay > 0;
        if (s.counter) s.pay = (s.pay * rules.counterNum) / rules.counterDen;
    }

    function resolveRound(
        Rules memory rules,
        Fighter memory a,
        Fighter memory b,
        Command memory ca,
        Command memory cb,
        int256 z,
        int256 c,
        bool voided
    ) internal pure returns (RoundResult memory r) {
        r.z = z;
        if (voided) return r;
        r.a = _side(rules, a, ca, cb, z, c);
        r.b = _side(rules, b, cb, ca, z, c);
        int256 diff = _abs(r.a.pay - r.b.pay);
        if (diff < rules.tie) {
            a.meter = _min(a.meter + rules.meterWin, rules.meterCap);
            b.meter = _min(b.meter + rules.meterWin, rules.meterCap);
            return r;
        }
        r.damage = rules.damageBase + (2 * _min(diff, rules.diffCap)) / WAD;
        r.loser = r.a.pay > r.b.pay ? 2 : 1;
        (Fighter memory lose, Fighter memory win) = r.loser == 2 ? (b, a) : (a, b);
        lose.hp = lose.hp > r.damage ? lose.hp - r.damage : int256(0);
        lose.meter = _min(lose.meter + rules.meterLoss, rules.meterCap);
        win.meter = _min(win.meter + rules.meterWin, rules.meterCap);
    }

    function begin(Rules memory rules, int256 sigmaPpm) internal pure returns (MatchState memory m) {
        if (sigmaPpm < rules.sigmaMin || sigmaPpm > rules.sigmaMax) revert SigmaBounds();
        m.a = Fighter(rules.hpStart, rules.meterStart);
        m.b = Fighter(rules.hpStart, rules.meterStart);
    }

    /// @notice Closes the match if no further round is needed. Returns true while another round must be played.
    function needsRound(Rules memory rules, MatchState memory m) internal pure returns (bool) {
        if (m.done) return false;
        if (m.r >= rules.maxRounds || (m.r >= rules.regularRounds && m.a.hp != m.b.hp)) {
            m.done = true;
            if (m.a.hp == m.b.hp) {
                m.reason = REASON_DRAW;
            } else {
                m.winner = m.a.hp > m.b.hp ? 1 : 2;
                m.reason = REASON_HP;
            }
            return false;
        }
        return true;
    }

    function _forfeits(bool missing, Command memory cmd) private pure returns (bool) {
        return missing || !validMove(cmd.move) || !validRead(cmd.read);
    }

    /// @notice True if nobody forfeits this round, so the referee may rate it.
    function isScored(MatchRound memory x) internal pure returns (bool) {
        return !_forfeits(x.aMissing, x.a) && !_forfeits(x.bMissing, x.b);
    }

    /// @notice Applies the next round. A forfeit ends the match before the round is scored, even if it is void.
    function applyRound(Rules memory rules, MatchState memory m, MatchRound memory x, int256 sigmaPpm, int256 c)
        internal
        pure
        returns (RoundResult memory r)
    {
        m.r += 1;
        bool fa = _forfeits(x.aMissing, x.a);
        bool fb = _forfeits(x.bMissing, x.b);
        if (fa || fb) {
            m.done = true;
            m.reason = REASON_FORFEIT;
            m.winner = fa && fb ? 0 : fa ? 2 : 1;
            return r;
        }
        if (x.voided) return r;
        r = resolveRound(rules, m.a, m.b, x.a, x.b, zWad(x.p0, x.p1, sigmaPpm), c, false);
        if (m.a.hp == 0 || m.b.hp == 0) {
            m.done = true;
            m.reason = REASON_KO;
            m.winner = m.b.hp == 0 ? 1 : 2;
        }
    }

    function resolveMatch(Rules memory rules, int256 sigmaPpm, int256 c, MatchRound[] memory rounds)
        internal
        pure
        returns (MatchState memory m)
    {
        m = begin(rules, sigmaPpm);
        while (needsRound(rules, m)) {
            if (m.r >= rounds.length) revert Truncated();
            applyRound(rules, m, rounds[m.r], sigmaPpm, c);
        }
    }
}
