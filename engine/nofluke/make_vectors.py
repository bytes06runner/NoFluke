"""Writes shared/vectors/referee.json: the same cases must pass in Python, TypeScript and Solidity."""
import json
import random
from pathlib import Path

from .params import load_params
from .referee import BURST, DOWN, GUARD, UP, WAD, Referee, ln_wad

OUT = Path(__file__).resolve().parents[2] / "shared" / "vectors" / "referee.json"
FLAT = OUT.with_name("referee-flat.json")
FLAT_WIDTH = 12 + 2 * 15 + 6
P0 = 10_000_000_000
LN_CASES = [1, 2, 999, 10**6, 10**9, WAD // 3, WAD // 2, WAD - 1, WAD, WAD + 1, 3 * WAD // 2, 2 * WAD, 3 * WAD, 600 * WAD, 132 * 100 * WAD, 10**30, 10**40, 2**255 - 1]


def fighter_json(s):
    return {
        "n": [str(x) for x in s.n],
        "nShort": [str(x) for x in s.n_short],
        "logW": str(s.logW),
        "lambda": str(s.lambda_),
        "A": str(s.A),
        "logL": str(s.logL),
        "rounds": s.rounds,
        "kAtCert": s.k_at_cert,
        "lapsed": s.lapsed,
    }


def feed_json(f):
    return {
        "meanZ": str(f.mean_z),
        "meanAbs": str(f.mean_abs),
        "meanZShort": str(f.mean_z_short),
        "meanAbsShort": str(f.mean_abs_short),
        "varReturn": str(f.var_return),
        "count": f.count,
    }


class History:
    """Runs a scripted history and records the state after every step."""

    def __init__(self, name, params, feed):
        self.name, self.ref, self.feed, self.steps = name, Referee(params), feed, []
        self.p = params
        self.t = 50_000_000 * params.tape_s

    def round(self, a, move_a, k_a, b, move_b, k_b, z, advance=True):
        sigma = self.ref.sigma_wad(self.feed)
        p1 = P0 + (P0 * int(z * 10**6) * sigma) // (10**6 * WAD)
        self.ref.record_round(self.feed, self.t, P0, p1, self.p.storm_c[self.feed], a, move_a, k_a, b, move_b, k_b)
        self.steps.append(
            {"kind": "round", "feed": self.feed, "t": self.t, "p0": str(P0), "p1": str(p1), "c": str(self.p.storm_c[self.feed]),
             "a": a, "moveA": move_a, "kA": k_a, "b": b, "moveB": move_b, "kB": k_b, **self._after()}
        )
        if advance:
            self.t += self.p.tape_s

    def forfeit(self, a, k):
        self.ref.record_forfeit(a, k)
        self.steps.append({"kind": "forfeit", "a": a, "kA": k, **self._after()})

    def _after(self):
        return {
            "fighters": {k: fighter_json(v) for k, v in self.ref.fighters.items()},
            "feedAfter": feed_json(self.ref.feed(self.feed)),
        }

    def out(self):
        return {"name": self.name, "steps": self.steps}


def build(params):
    feed = params.feed_ids[0]
    rng = random.Random(params.raw["validation"]["rngSeed"])
    hs = []

    def new(name):
        h = History(name, params, feed)
        hs.append(h)
        return h

    h = new("uniform random moves")
    for _ in range(40):
        h.round("A", rng.randrange(4), 2, "B", rng.randrange(4), 2, rng.gauss(0, 1))
    h = new("always up against always guard")
    for _ in range(30):
        h.round("A", UP, 2, "B", GUARD, 2, rng.gauss(0, 1))
    h = new("burst and guard against fat tails")
    for _ in range(30):
        h.round("A", BURST, 1, "B", GUARD, 1, rng.choice([-6, -2, -0.1, 0, 0.1, 2, 6]))
    h = new("habit switcher")
    for i in range(40):
        h.round("A", GUARD if i < 20 else BURST, 2, "B", DOWN, 2, rng.gauss(0, 1))
    h = new("direction reader reaches the bar")
    for i in range(160):
        z = 2.0 if i % 2 else -2.0
        h.round("A", UP if z > 0 else DOWN, 2, "B", rng.randrange(4), 2, z)
    h = new("lambda clamps at zero")
    for i in range(30):
        z = 2.0 if i % 2 else -2.0
        h.round("A", DOWN if z > 0 else UP, 2, "B", GUARD, 2, z)
    h = new("lambda clamps at the maximum")
    for i in range(60):
        z = 3.0 if i % 2 else -3.0
        h.round("A", UP if z > 0 else DOWN, 1, "B", GUARD, 1, z)
    h = new("family grows mid history")
    for i in range(120):
        z = 2.0 if i % 2 else -2.0
        h.round("A", UP if z > 0 else DOWN, 2 + i // 8, "B", GUARD, 1, z)
    h = new("forfeits mixed with rounds")
    for i in range(40):
        z = 2.0 if i % 2 else -2.0
        if i % 5 == 4:
            h.forfeit("A", 2)
        else:
            h.round("A", UP if z > 0 else DOWN, 2, "B", GUARD, 2, z)
    h = new("overlapping tapes leave the feed unchanged")
    for i in range(12):
        h.round("A", i % 4, 2, "B", GUARD, 2, rng.gauss(0, 1), advance=i % 3 == 2)
    h = new("certify then lapse")
    for i in range(400):
        z = 2.0 if i % 2 else -2.0
        if i < 160:
            h.round("A", UP if z > 0 else DOWN, 2, "B", GUARD, 2, z)
        else:
            h.round("A", DOWN if z > 0 else UP, 2, "B", GUARD, 2, z)
        if h.ref.fighter("A").lapsed:
            break
    h = new("flat prices hit the sigma floor")
    for _ in range(30):
        h.round("A", GUARD, 2, "B", BURST, 2, 0)
    h = new("zero z and exact breakpoint")
    for _ in range(20):
        h.round("A", GUARD, 2, "B", BURST, 2, params.storm_c[feed] / WAD)
    return {
        "lnWad": [{"x": str(x), "y": str(ln_wad(x))} for x in LN_CASES],
        "bars": [{"k": k, "lnBar": str(Referee(params).ln_bar(k))} for k in (1, 2, 3, 10, 11, 20, 21, 1000)],
        "histories": [x.out() for x in hs],
    }


def _fighter_row(state):
    if state is None:
        return ["0"] * 15
    return [*state["n"], *state["nShort"], state["logW"], state["lambda"], state["A"], state["logL"], str(state["rounds"]), str(state["kAtCert"]), str(int(state["lapsed"]))]


def flatten(data, params):
    """One flat array per history, because Foundry parses a large nested file slowly."""
    feed_index = {f: i for i, f in enumerate(params.feed_ids)}
    who = {"A": "1", "B": "2"}
    out = []
    for h in data["histories"]:
        row = []
        for s in h["steps"]:
            f = s["fighters"]
            if s["kind"] == "round":
                row += ["1", str(feed_index[s["feed"]]), str(s["t"]), s["p0"], s["p1"], s["c"], who[s["a"]], str(s["moveA"]), str(s["kA"]), who[s["b"]], str(s["moveB"]), str(s["kB"])]
                fa = s["feedAfter"]
            else:
                row += ["2", "0", "0", "0", "0", "0", who[s["a"]], "0", str(s["kA"]), "0", "0", "0"]
                fa = None
            row += _fighter_row(f.get("A")) + _fighter_row(f.get("B"))
            row += ["0"] * 6 if fa is None else [fa["meanZ"], fa["meanAbs"], fa["meanZShort"], fa["meanAbsShort"], fa["varReturn"], str(fa["count"])]
        out.append(row)
    return {
        "width": FLAT_WIDTH,
        "count": len(out),
        "lnX": [c["x"] for c in data["lnWad"]],
        "lnY": [c["y"] for c in data["lnWad"]],
        "barK": [str(c["k"]) for c in data["bars"]],
        "barY": [c["lnBar"] for c in data["bars"]],
        "h": out,
    }


if __name__ == "__main__":
    params = load_params()
    data = build(params)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data) + "\n")
    FLAT.write_text(json.dumps(flatten(data, params)) + "\n")
    steps = sum(len(h["steps"]) for h in data["histories"])
    print(f"wrote {OUT.name}: {len(data['histories'])} histories, {steps} steps, {len(data['lnWad'])} ln cases")
