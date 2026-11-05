"""Match rules: the integer reference. TypeScript and Solidity must match it bit for bit."""
import json
from dataclasses import dataclass

from .params import CONFIG
from .referee import WAD, tdiv

PPM_SCALE = 10**24  # WAD * 1e6, because sigma is in parts per million


class SigmaBounds(Exception):
    pass


class BadPrice(Exception):
    pass


class Truncated(Exception):
    pass


@dataclass(frozen=True)
class Rules:
    hp_start: int
    meter_start: int
    meter_cap: int
    overdrive_cost: int
    meter_win: int
    meter_loss: int
    damage_base: int
    diff_cap: int
    tie: int
    regular_rounds: int
    max_rounds: int
    sigma_min: int
    sigma_max: int
    payoff_per_z: int
    counter_num: int
    counter_den: int


def load_rules(path=CONFIG) -> Rules:
    m = json.loads(path.read_text())["match"]
    return Rules(
        m["hpStart"], m["meterStart"], m["meterCap"], m["overdriveCost"], m["meterWin"], m["meterLoss"], m["damageBase"],
        m["damageDiffCapPoints"] * WAD, m["tiePoints"] * WAD, m["regularRounds"], m["maxRounds"], m["sigmaMinPpm"], m["sigmaMaxPpm"],
        m["payoffPerZ"], m["counterHitNumerator"], m["counterHitDenominator"],
    )


@dataclass
class Fighter:
    hp: int
    meter: int


@dataclass(frozen=True)
class Command:
    move: int
    read: int
    overdrive: bool


@dataclass(frozen=True)
class Side:
    pay: int
    od: bool
    counter: bool


@dataclass(frozen=True)
class RoundResult:
    z: int
    damage: int
    loser: int
    a: Side
    b: Side


@dataclass(frozen=True)
class MatchRound:
    p0: int
    p1: int
    voided: bool
    a_missing: bool
    b_missing: bool
    a: Command
    b: Command


@dataclass(frozen=True)
class MatchResult:
    winner: int
    reason: int
    rounds: int
    a: Fighter
    b: Fighter


REASON_KO, REASON_HP, REASON_FORFEIT, REASON_DRAW = 0, 1, 2, 3


def abs_(x: int) -> int:
    return -x if x < 0 else x


def move_type(move: int) -> int:
    return 0 if move <= 1 else move - 1


def valid_move(move: int) -> bool:
    return move <= 3


def valid_read(read: int) -> bool:
    return read <= 2


def z_wad(p0: int, p1: int, sigma_ppm: int) -> int:
    if p0 <= 0 or p1 <= 0:
        raise BadPrice
    return tdiv((p1 - p0) * PPM_SCALE, p0 * sigma_ppm)


def is_void(p0, conf0, expo0, p1, conf1, expo1, conf_cap_bps) -> bool:
    if p0 <= 0 or p1 <= 0 or expo0 != expo1:
        return True
    if conf_cap_bps == 0:
        return False
    return conf0 * 10_000 > conf_cap_bps * p0 or conf1 * 10_000 > conf_cap_bps * p1


def base_payoff(rules: Rules, move: int, z: int, c: int) -> int:
    k = rules.payoff_per_z
    if move == 0:
        return k * z
    if move == 1:
        return -k * z
    if move == 2:
        return k * (c - abs_(z))
    return k * (abs_(z) - c)


def _side(rules: Rules, me: Fighter, cmd: Command, opp: Command, z: int, c: int) -> Side:
    od = cmd.overdrive and me.meter >= rules.overdrive_cost
    if od:
        me.meter -= rules.overdrive_cost
    pay = base_payoff(rules, cmd.move, z, c)
    if od:
        pay *= 2
    counter = cmd.read == move_type(opp.move) and pay > 0
    if counter:
        pay = tdiv(pay * rules.counter_num, rules.counter_den)
    return Side(pay, od, counter)


def resolve_round(rules: Rules, a: Fighter, b: Fighter, ca: Command, cb: Command, z: int, c: int, voided: bool) -> RoundResult:
    if voided:
        return RoundResult(z, 0, 0, Side(0, False, False), Side(0, False, False))
    sa = _side(rules, a, ca, cb, z, c)
    sb = _side(rules, b, cb, ca, z, c)
    diff = abs_(sa.pay - sb.pay)
    damage, loser = 0, 0
    if diff < rules.tie:
        a.meter = min(a.meter + rules.meter_win, rules.meter_cap)
        b.meter = min(b.meter + rules.meter_win, rules.meter_cap)
    else:
        damage = rules.damage_base + tdiv(2 * min(diff, rules.diff_cap), WAD)
        loser = 2 if sa.pay > sb.pay else 1
        lose, win = (b, a) if loser == 2 else (a, b)
        lose.hp = max(lose.hp - damage, 0)
        lose.meter = min(lose.meter + rules.meter_loss, rules.meter_cap)
        win.meter = min(win.meter + rules.meter_win, rules.meter_cap)
    return RoundResult(z, damage, loser, sa, sb)


def _forfeits(missing: bool, cmd: Command) -> bool:
    return missing or not valid_move(cmd.move) or not valid_read(cmd.read)


def resolve_match(rules: Rules, sigma_ppm: int, c: int, rounds: list) -> MatchResult:
    if sigma_ppm < rules.sigma_min or sigma_ppm > rules.sigma_max:
        raise SigmaBounds
    a = Fighter(rules.hp_start, rules.meter_start)
    b = Fighter(rules.hp_start, rules.meter_start)
    r = 0
    while True:
        if r >= rules.max_rounds or (r >= rules.regular_rounds and a.hp != b.hp):
            if a.hp == b.hp:
                return MatchResult(0, REASON_DRAW, r, a, b)
            return MatchResult(1 if a.hp > b.hp else 2, REASON_HP, r, a, b)
        if r >= len(rounds):
            raise Truncated
        m = rounds[r]
        r += 1
        fa, fb = _forfeits(m.a_missing, m.a), _forfeits(m.b_missing, m.b)
        if fa or fb:
            winner = 0 if fa and fb else (2 if fa else 1)
            return MatchResult(winner, REASON_FORFEIT, r, a, b)
        if m.voided:
            continue
        resolve_round(rules, a, b, m.a, m.b, z_wad(m.p0, m.p1, sigma_ppm), c, False)
        if a.hp == 0 or b.hp == 0:
            return MatchResult(1 if b.hp == 0 else 2, REASON_KO, r, a, b)
