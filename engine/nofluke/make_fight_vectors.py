"""Writes shared/vectors/fightmath.json: rounds, matches, must-reject cases and void checks, as flat integers."""
import json
import random
from dataclasses import replace
from pathlib import Path

from .fightmath import BadPrice, Command, Fighter, MatchRound, SigmaBounds, Truncated, is_void, load_rules, resolve_match, resolve_round, z_wad
from .params import load_params
from .referee import WAD

OUT = Path(__file__).resolve().parents[2] / "shared" / "vectors" / "fightmath.json"
ROUND_WIDTH = 28
P0 = 10**10
BAD_SIGMA, BAD_PRICE, TRUNCATED = 1, 2, 3


def _i(b):
    return int(b)


def round_case(rules, p0, p1, sigma, c, a, b, ca, cb, voided=False):
    z = z_wad(p0, p1, sigma)
    fa, fb = Fighter(*a), Fighter(*b)
    r = resolve_round(rules, fa, fb, Command(*ca), Command(*cb), z, c, voided)
    row = [p0, p1, sigma, c, a[0], a[1], b[0], b[1], ca[0], ca[1], _i(ca[2]), cb[0], cb[1], _i(cb[2]), _i(voided)]
    row += [r.z, r.damage, r.loser, r.a.pay, _i(r.a.od), _i(r.a.counter), r.b.pay, _i(r.b.od), _i(r.b.counter), fa.hp, fa.meter, fb.hp, fb.meter]
    return [str(x) for x in row]


def match_rounds_row(rounds):
    row = [len(rounds)]
    for m in rounds:
        row += [m.p0, m.p1, _i(m.voided), _i(m.a_missing), _i(m.b_missing), m.a.move, m.a.read, _i(m.a.overdrive), m.b.move, m.b.read, _i(m.b.overdrive)]
    return row


def match_case(rules, sigma, c, rounds):
    m = resolve_match(rules, sigma, c, rounds)
    return [str(x) for x in [sigma, c, *match_rounds_row(rounds), m.winner, m.reason, m.rounds, m.a.hp, m.a.meter, m.b.hp, m.b.meter]]


def reject_case(rules, sigma, c, rounds):
    try:
        resolve_match(rules, sigma, c, rounds)
    except SigmaBounds:
        code = BAD_SIGMA
    except BadPrice:
        code = BAD_PRICE
    except Truncated:
        code = TRUNCATED
    else:
        raise AssertionError("expected a rejection")
    return [str(x) for x in [sigma, c, *match_rounds_row(rounds), code]]


def build(rules, params):
    c = next(iter(params.storm_c.values()))
    start = (rules.hp_start, rules.meter_start)
    sig = 1000
    rng = random.Random(params.raw["validation"]["rngSeed"])

    def price(z_milli, sigma=sig, p0=P0):
        return p0 + p0 * z_milli * sigma // 10**9

    S, D, G, B = (0, 0, False), (1, 0, False), (2, 0, False), (3, 0, False)
    full = (rules.hp_start, rules.meter_cap)
    od = (rules.hp_start, rules.overdrive_cost)
    rounds = [
        round_case(rules, P0, P0, sig, c, start, start, G, B),
        round_case(rules, P0, P0, sig, c, start, start, S, S),
        round_case(rules, P0, price(1000), sig, c, start, start, S, D),
        round_case(rules, P0, price(-1000), sig, c, start, start, S, D),
        round_case(rules, P0, price(-370), sig, c, start, start, S, D),
        round_case(rules, P0, price(2000), sig, c, start, start, G, B),
        round_case(rules, P0, price(c * 1000 // WAD), sig, c, start, start, G, B),
        round_case(rules, P0, price(50), sig, c, start, start, S, D),
        round_case(rules, P0, price(49), sig, c, start, start, S, D),
        round_case(rules, P0, price(1000), sig, c, start, start, (0, 0, True), D),
        round_case(rules, P0, price(50000), sig, c, start, start, S, D),
        round_case(rules, P0, price(-40000), sig, c, start, start, S, D),
        round_case(rules, P0, price(1000), sig, c, od, start, (0, 0, True), G),
        round_case(rules, P0, price(1000), sig, c, (rules.hp_start, rules.overdrive_cost - 1), start, (0, 0, True), G),
        round_case(rules, P0, price(-1000), sig, c, od, start, (0, 0, True), G),
        round_case(rules, P0, price(1000), sig, c, start, start, (0, 1, False), G),
        round_case(rules, P0, price(-1000), sig, c, start, start, (0, 1, False), G),
        round_case(rules, P0, price(1000), sig, c, od, start, (0, 1, True), G),
        round_case(rules, P0, price(1000), sig, c, od, od, (0, 0, True), (1, 0, True)),
        round_case(rules, P0, price(-1000), sig, c, full, full, S, D),
        round_case(rules, P0, price(1000), sig, c, full, full, S, D),
        round_case(rules, P0, price(1000), sig, c, start, (5, 10), S, D),
        round_case(rules, P0, price(1000), sig, c, start, start, S, D, voided=True),
        round_case(rules, P0, price(1000), sig, c, full, start, (0, 0, True), D, voided=True),
        round_case(rules, P0, P0, sig, c, start, start, G, G),
        round_case(rules, P0, price(3000), sig, c, start, start, B, B),
        round_case(rules, P0, price(1000, 100), 100, c, start, start, S, D),
        round_case(rules, P0, price(1000, 5000), 5000, c, start, start, S, D),
        round_case(rules, P0, price(1000), sig, 2 * c, start, start, G, B),
        round_case(rules, 1000, 1001, sig, c, start, start, S, D),
        round_case(rules, 1000, 999, sig, c, start, start, S, D),
    ]
    for _ in range(40):
        a = (rng.randint(1, rules.hp_start), rng.randint(0, rules.meter_cap))
        b = (rng.randint(1, rules.hp_start), rng.randint(0, rules.meter_cap))
        ca = (rng.randrange(4), rng.randrange(3), rng.random() < 0.5)
        cb = (rng.randrange(4), rng.randrange(3), rng.random() < 0.5)
        rounds.append(round_case(rules, P0, price(rng.randint(-4000, 4000)), sig, c, a, b, ca, cb))

    def mr(p1, a=(0, 0, False), b=(1, 0, False), **kw):
        return MatchRound(P0, p1, kw.get("voided", False), kw.get("a_missing", False), kw.get("b_missing", False), Command(*a), Command(*b))

    win = mr(price(2000))
    small = mr(price(50))
    flat = mr(P0, G, G)
    void = mr(P0, voided=True)
    bad_move_a = mr(price(50), a=(4, 0, False))
    matches = [
        match_case(rules, sig, c, [win] * 3),
        match_case(rules, sig, c, [small] * 5),
        match_case(rules, sig, c, [flat] * 5 + [small]),
        match_case(rules, sig, c, [flat] * 6),
        match_case(rules, sig, c, [small, small, mr(price(50), a_missing=True)]),
        match_case(rules, sig, c, [small, mr(price(50), b=(5, 0, False))]),
        match_case(rules, sig, c, [mr(price(50), a=(0, 3, False))]),
        match_case(rules, sig, c, [mr(price(50), a_missing=True, b_missing=True)]),
        match_case(rules, sig, c, [void, void, *[small] * 5]),
        match_case(rules, sig, c, [mr(price(-2000)), mr(price(-2000)), mr(price(3000), a=(0, 0, True)), mr(price(3000), a=(0, 0, True)), small]),
        match_case(rules, 100, c, [mr(price(2000, 100))] * 3),
        match_case(rules, 5000, c, [mr(price(2000, 5000))] * 3),
        match_case(rules, sig, c, [bad_move_a]),
        match_case(rules, sig, c, [mr(price(50), b=(255, 0, False))]),
        match_case(rules, sig, c, [mr(price(50), b=(0, 255, False))]),
        match_case(rules, sig, c, [flat] * 5 + [mr(price(50), a_missing=True)]),
        match_case(rules, sig, c, [mr(price(50), voided=True, a_missing=True)]),
        match_case(rules, sig, c, [mr(price(50), a_missing=True, b=(9, 0, False))]),
        match_case(rules, sig, c, [mr(price(50), a=(9, 0, False), b=(9, 0, False))]),
        match_case(rules, sig, c, [mr(P0, G, G)] * 5 + [void]),
        match_case(rules, sig, c, [small] * 2 + [mr(price(-50))] * 2 + [void, small]),
        match_case(rules, sig, c, [void] * 6),
        match_case(rules, sig, c, [void, win, win, win]),
        match_case(rules, sig, c, [void, mr(price(1000), a=(0, 0, True)), mr(price(2000), a=(0, 0, True)), win, win]),
        match_case(rules, sig, c, [win] * 6),
    ]
    # A KO in sudden death: tie after five rounds of trades, then one big hit on low HP.
    trade = [mr(price(2000)), mr(price(-2000)), flat, flat, flat]
    matches.append(match_case(rules, sig, c, trade + [win]))
    for _ in range(12):
        rs = []
        for _ in range(rules.max_rounds):
            rs.append(mr(price(rng.randint(-3000, 3000)), (rng.randrange(4), rng.randrange(3), rng.random() < 0.5), (rng.randrange(4), rng.randrange(3), rng.random() < 0.5), voided=rng.random() < 0.1))
        matches.append(match_case(rules, sig, c, rs))
    rejects = [
        reject_case(rules, sig, c, [small, small]),
        reject_case(rules, sig, c, [flat] * 5),
        reject_case(rules, rules.sigma_min - 1, c, [small] * 5),
        reject_case(rules, rules.sigma_max + 1, c, [small] * 5),
        reject_case(rules, sig, c, []),
        reject_case(rules, sig, c, [mr(-1)]),
        reject_case(rules, sig, c, [small] * 2 + [flat] + [void]),
    ]
    voids = []
    for case in [
        (10000, 10, -8, 10000, 10, -8, 100), (10000, 100, -8, 10000, 100, -8, 100), (10000, 101, -8, 10000, 100, -8, 100),
        (10000, 100, -8, 10000, 101, -8, 100), (10000, 10**6, -8, 10000, 10**6, -8, 0), (0, 1, -8, 100, 1, -8, 100),
        (100, 1, -8, 0, 1, -8, 100), (-5, 1, -8, 100, 1, -8, 100), (100, 1, -8, 100, 1, -7, 100), (10000, 25, -8, 10000, 25, -8, 100), (10**15, 10**13, -8, 10**15, 10**13 + 1, -8, 100),
    ]:
        voids.append([str(x) for x in (*case, _i(is_void(*case)))])
    return {"roundWidth": ROUND_WIDTH, "rounds": [x for row in rounds for x in row], "roundCount": len(rounds), "matches": matches, "matchCount": len(matches), "rejects": rejects, "rejectCount": len(rejects), "voids": voids, "voidCount": len(voids)}


if __name__ == "__main__":
    data = build(load_rules(), load_params())
    OUT.write_text(json.dumps(data) + "\n")
    print(f"wrote {OUT.name}: {data['roundCount']} rounds, {data['matchCount']} matches, {data['rejectCount']} rejects, {data['voidCount']} voids")
