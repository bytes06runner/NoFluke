"""Attack catalogue and power measurements on real recorded prices. Writes docs/reports/referee-validation.*"""
import argparse
import json
import time
from dataclasses import replace
from pathlib import Path

import numpy as np
from scipy.stats import beta

from nofluke.params import load_params

from .fast import BURST, DOWN, GUARD, UP, WAD, FastParams, feed_paths, run_career
from .tapes import load_tape, plain_returns, sample_careers

REPORTS = Path(__file__).resolve().parents[2] / "docs" / "reports"


def upper95(hits: int, n: int) -> float:
    """Clopper-Pearson one-sided 95% upper bound."""
    return 1.0 if hits >= n else float(beta.ppf(0.95, hits + 1, n - hits))


def rolling_abs_returns(close, lookbacks):
    """Mean absolute 1 s log return over each look-back, ending at each second."""
    abs_ret = np.abs(np.diff(np.log(close), prepend=np.log(close[0])))
    total = np.cumsum(abs_ret)
    out = []
    for w in lookbacks:
        f = np.zeros(len(close))
        f[w:] = (total[w:] - total[:-w]) / w
        out.append(f)
    return out


class World:
    """One feed's data, plus everything fitted on the fit days only."""

    def __init__(self, params, slug, feed_id):
        raw = params.raw
        self.params = params
        self.fp = FastParams.of(params)
        self.slug = slug
        self.feed_id = feed_id
        self.tape_s = params.tape_s
        self.per_match = raw["match"]["regularRounds"]
        self.gap_s = raw["validation"]["matchGapS"]
        self.lead_s = raw["timing"]["anchorMarginS"] + raw["validation"]["decisionLeadS"]
        self.tape = load_tape(slug, raw["storm"]["lookbackS"], raw["storm"]["minSamplesS"])
        self.fit_share = raw["validation"]["fitDays"] / raw["validation"]["dataDays"]
        self.sigma_init = params.sigma_init_ppm[feed_id] * 1e-6
        factor = int(raw["storm"]["breakpointFactorWad"]) / WAD
        rets = plain_returns(self.tape, self.tape_s, 0.0, self.fit_share)
        self.sigma_fit = float(rets.std())
        # The storm line is fitted on the referee's own z scale, on fit days only.
        self.c = factor * float(np.mean(np.abs(rets / self.sigma_fit)))
        self.features = rolling_abs_returns(self.tape.close, raw["storm"]["forecastLookbacksS"])
        self.theta = self._fit_theta()

    def careers(self, rng, n, rounds, lo=0.0, hi=1.0):
        returns, storm, t0 = sample_careers(self.tape, rng, n, rounds, self.tape_s, self.per_match, self.gap_s, self.lead_s, lo, hi)
        signals = np.stack([f[t0 - self.lead_s] * np.sqrt(self.tape_s) for f in self.features], axis=-1)
        return returns, storm, signals

    def _fit_theta(self) -> float:
        """The single-signal reader's threshold: the median on fit days, so its habits stay balanced."""
        rng = np.random.default_rng(self.params.raw["validation"]["rngSeed"])
        returns, storm, signals = self.careers(rng, 1500, 500, 0.0, self.fit_share)
        paths = feed_paths(self.fp, returns, self.c, self.sigma_init)
        self.beta = self._fit_forecast(paths, signals)
        forecast = self.forecast(paths, signals)
        self.forecast_median = float(np.median(forecast))
        return float(np.median(storm / paths.sigma))

    def _fit_forecast(self, paths, signals) -> np.ndarray:
        """Least squares of the next round's |z| on the signals divided by sigma, on fit days only."""
        scaled = (signals / paths.sigma[..., None]).reshape(-1, signals.shape[-1])
        design = np.column_stack([scaled, np.ones(len(scaled))])
        target = np.abs(np.clip(paths.z, -self.fp.z_clip, self.fp.z_clip)).ravel()
        return np.linalg.lstsq(design, target, rcond=None)[0]

    def forecast(self, paths, signals) -> np.ndarray:
        return (signals / paths.sigma[..., None]) @ self.beta[:-1] + self.beta[-1]


def moves_constant(n, t, move):
    return np.full((n, t), move, dtype=np.int64)


def moves_uniform(rng, n, t):
    return rng.integers(0, 4, size=(n, t))


def moves_switcher(n, t, first=100):
    m = np.full((n, t), BURST, dtype=np.int64)
    m[:, :first] = GUARD
    return m


def moves_drifter(rng, n, t):
    share = np.arange(t) / t
    return np.where(rng.random((n, t)) < share, BURST, GUARD)


def moves_periodic(n, t, period, a=GUARD, b=BURST):
    phase = (np.arange(t) // period) % 2
    return np.broadcast_to(np.where(phase == 0, a, b), (n, t)).copy()


def moves_schedule(rng, n, t, segment, weights):
    """A market-independent habit schedule: each segment plays its own mix of moves."""
    seg = (np.arange(t) // segment) % len(weights)
    cum = np.cumsum(weights, axis=1)
    u = rng.random((n, t))
    return (u[..., None] > cum[seg][None, :, :]).sum(-1).clip(0, 3)


class Runner:
    def __init__(self, world, seeds, rounds, kappa=None):
        self.w = world
        self.seeds = seeds
        self.rounds = rounds
        self.seed0 = world.params.raw["validation"]["rngSeed"]
        fp = world.fp
        if kappa is not None:
            fp = replace(fp, kappa=kappa)
        self.fp = fp

    def rng(self, salt):
        return np.random.default_rng([self.seed0, salt])

    def paths(self, rng, n=None, rounds=None, lo=0.0, hi=1.0, mask_fn=None):
        n = n or self.seeds
        rounds = rounds or self.rounds
        returns, storm, signals = self.w.careers(rng, n, rounds, lo, hi)
        return feed_paths(self.fp, returns, self.w.c, self.w.sigma_init), (storm, signals)

    def false_rate(self, salt, make_moves, k=2, forfeit_fn=None, n=None, rounds=None):
        rng = self.rng(salt)
        n = n or self.seeds
        rounds = rounds or self.rounds
        paths, _ = self.paths(rng, n, rounds)
        moves = make_moves(rng, n, rounds)
        forfeit = None if forfeit_fn is None else forfeit_fn(paths, moves)
        c = run_career(self.fp, paths, moves, k, self.w.c, forfeit=forfeit)
        hits = int((c.crossed_at >= 0).sum())
        return {"hits": hits, "n": n, "rate": hits / n, "ub95": upper95(hits, n), "gMean": float(np.mean(c.v_mean**2 / (2 * np.maximum(c.v2_mean, 1e-9))))}


def attack_table(run: Runner, optimiser_candidates: int, family_size: int):
    r = run
    table = {}

    def add(key, label, res):
        table[key] = {"label": label, **res}

    add("1", "Stop at a lucky moment (uniform random, checked every round)", r.false_rate(1, lambda g, n, t: moves_uniform(g, n, t)))
    for name, move in (("up", UP), ("down", DOWN), ("guard", GUARD), ("burst", BURST)):
        add(f"2-{name}", f"Always {name.capitalize()}", r.false_rate(2 + move * 10, lambda g, n, t, m=move: moves_constant(n, t, m)))
    add("3", "Uniform random", r.false_rate(3, lambda g, n, t: moves_uniform(g, n, t), k=1))
    add("4-switch", "Habit switcher: Guard 100 rounds, then Burst", r.false_rate(4, lambda g, n, t: moves_switcher(n, t)))
    add("4-drift", "Slow drifter: Guard drifting to Burst", r.false_rate(5, lambda g, n, t: moves_drifter(g, n, t)))
    worst = None
    for period in (4, 8, 16, 32, 64, 128, 256):
        res = r.false_rate(6 + period, lambda g, n, t, p=period: moves_periodic(n, t, p))
        table[f"5-{period}"] = {"label": f"Periodic switching, every {period} rounds", **res}
        if worst is None or res["rate"] > worst["rate"]:
            worst = {"label": f"Periodic switching, worst period ({period} rounds)", **res}
    table["5"] = worst
    table["6"] = optimiser(r, optimiser_candidates)
    table["7"] = staggered_family(r, family_size)
    add("8", "Selective reveal: forfeit every round that lost", r.false_rate(8, lambda g, n, t: moves_uniform(g, n, t), forfeit_fn=_selective_forfeit))
    worst_period = int(table["5"]["label"].split("(")[1].split(" ")[0])
    add("5-long", f"Periodic switching, worst period, twice the career length", r.false_rate(17, lambda g, n, t: moves_periodic(n, t, worst_period), rounds=2 * r.rounds))
    return table


def _selective_forfeit(paths, moves):
    z = np.clip(paths.z, -3, 3)
    n, t = moves.shape
    pay = np.stack([10 * z, -10 * z, -10 * np.abs(z), 10 * np.abs(z)], axis=-1)
    own = np.take_along_axis(pay, moves[..., None], axis=-1)[..., 0]
    return own - pay.mean(-1) < 0


def optimiser(r: Runner, candidates: int):
    """Random search then local refinement over market-independent schedules. The winner is re-tested on fresh seeds."""
    rng = r.rng(600)
    screen = max(r.seeds // 10, 200)
    pool = []

    def score(segment, weights, salt):
        res = r.false_rate(salt, lambda g, n, t: moves_schedule(g, n, t, segment, weights), n=screen)
        return res["rate"], res["gMean"]

    first = int(candidates * 0.7)
    for i in range(first):
        segment = int(rng.choice([2, 4, 8, 16, 32, 64, 128, 256]))
        phases = int(rng.integers(2, 6))
        w = rng.dirichlet(np.full(4, float(rng.choice([0.1, 0.3, 1.0]))), size=phases)
        pool.append((*score(segment, w, 1000 + i), segment, w))
    pool.sort(key=lambda x: (x[0], x[1]), reverse=True)
    top = pool[:10]
    for i in range(candidates - first):
        _, _, segment, w = top[i % len(top)]
        w2 = np.abs(w + rng.normal(0, 0.1, w.shape))
        w2 = w2 / w2.sum(1, keepdims=True)
        seg2 = int(max(2, segment * rng.choice([0.5, 1, 2])))
        pool.append((*score(seg2, w2, 5000 + i), seg2, w2))
    pool.sort(key=lambda x: (x[0], x[1]), reverse=True)
    _, _, segment, w = pool[0]
    final = r.false_rate(9001, lambda g, n, t: moves_schedule(g, n, t, segment, w))
    return {"label": f"Optimiser search over {candidates} market-independent schedules: best, re-tested", "segment": segment, "bestScreenRate": pool[0][0], **final}


def staggered_family(r: Runner, size: int):
    rng = r.rng(700)
    n, t = r.seeds, r.rounds
    paths, _ = r.paths(rng)
    stagger = max(t // (size * 2), 1)
    entered = np.minimum(np.arange(t) // stagger + 1, size)
    k = np.broadcast_to(1 + entered, (n, t)).astype(float)
    any_hit = np.zeros(n, bool)
    for j in range(size):
        moves = moves_uniform(rng, n, t)
        start = np.full(n, j * stagger)
        c = run_career(r.fp, paths, moves, k, r.w.c, start=start)
        any_hit |= c.crossed_at >= 0
    hits = int(any_hit.sum())
    return {"label": f"Staggered family of {size} bots, one human", "hits": hits, "n": n, "rate": hits / n, "ub95": upper95(hits, n), "gMean": 0.0}


def planted_moves(rng, paths, c, edge):
    """Offline validation only: with probability `edge` the strategy sees whether the storm line is crossed this round."""
    n, t = paths.z.shape
    knows = rng.random((n, t)) < edge
    right = np.where(np.abs(paths.z) > c, BURST, GUARD)
    coin = np.where(rng.random((n, t)) < 0.5, BURST, GUARD)
    return np.where(knows, right, coin)


def quantile_or_none(crossed, q):
    n = len(crossed)
    done = np.sort(crossed[crossed >= 0])
    need = int(np.ceil(q * n))
    return None if len(done) < need else int(done[need - 1]) + 1


def power_row(r: Runner, moves_fn, k, salt, rounds, n, lo=0.0, hi=1.0, bet="ons"):
    rng = r.rng(salt)
    paths, signals = r.paths(rng, n, rounds, lo, hi)
    moves = moves_fn(rng, paths, signals)
    c = run_career(r.fp, paths, moves, k, r.w.c, bet=bet)
    return {
        "k": k,
        "share": float((c.crossed_at >= 0).mean()),
        "n50": quantile_or_none(c.crossed_at, 0.50),
        "n90": quantile_or_none(c.crossed_at, 0.90),
        "n99": quantile_or_none(c.crossed_at, 0.99),
        "g": float(np.mean(c.v_mean) ** 2 / (2 * np.mean(c.v2_mean))),
    }


def power_table(r: Runner, edges, power_rounds, n):
    w = r.w
    rows = []

    def single(rng, paths, x):
        return np.where(x[0] / np.maximum(paths.sigma, 1e-12) > w.theta, BURST, GUARD)

    def multi(rng, paths, x):
        return np.where(w.forecast(paths, x[1]) > w.forecast_median, BURST, GUARD)

    for k in (2, 11):
        rows.append({"strategy": "Single-signal storm reader (test days only)", **power_row(r, single, k, 100 + k, power_rounds, n, w.fit_share, 1.0)})
        rows.append({"strategy": "Multi-signal storm reader (test days only)", **power_row(r, multi, k, 150 + k, power_rounds, n, w.fit_share, 1.0)})
        for e in edges:
            rows.append({"strategy": f"Planted edge {e:.0%}", **power_row(r, lambda g, p, s, x=e: planted_moves(g, p, w.c, x), k, 200 + k + int(e * 1000), power_rounds, n)})
    compare = []
    for e in edges:
        for bet in ("ons", "plugin"):
            compare.append({"edge": e, "bet": bet, **power_row(r, lambda g, p, s, x=e: planted_moves(g, p, w.c, x), 2, 300 + int(e * 1000), power_rounds, n, bet=bet)})
    return rows, compare


def lapse_table(r: Runner, edge, rounds, n):
    """The detector should fire when a real edge stops, and stay quiet while it continues."""
    w = r.w
    rng = r.rng(800)
    paths, _ = r.paths(rng, n, rounds)
    keep = planted_moves(rng, paths, w.c, edge)
    switch_at = rounds // 2
    coin = np.where(rng.random(keep.shape) < 0.5, BURST, GUARD)
    stops = keep.copy()
    stops[:, switch_at:] = coin[:, switch_at:]
    against = keep.copy()
    against[:, switch_at:] = np.where(np.abs(paths.z[:, switch_at:]) > w.c, GUARD, BURST)
    out = []
    for label, moves in (("Edge continues", keep), ("Edge stops halfway (coin flips)", stops), ("Edge turns negative halfway", against)):
        c = run_career(r.fp, paths, moves, 2, w.c)
        cert = c.crossed_at >= 0
        lapsed = c.lapsed_at >= 0
        after = c.lapsed_at[lapsed] - switch_at
        out.append({"label": label, "certified": float(cert.mean()), "lapsed": float(lapsed.sum() / max(cert.sum(), 1)), "medianAfterSwitch": None if not len(after) else int(np.median(after))})
    return out


def calibrate_kappa(world, seeds, rounds, kappas, edges, power_rounds, power_n):
    """Finds the smallest κ that keeps every drift attack's 95% upper bound at or below α."""
    out = []
    for kappa in kappas:
        r = Runner(world, seeds, rounds, kappa=kappa)
        res = {
            "switch": r.false_rate(4, lambda g, n, t: moves_switcher(n, t)),
            "drift": r.false_rate(5, lambda g, n, t: moves_drifter(g, n, t)),
        }
        for period in (4, 8, 16, 32, 64, 128, 256):
            res[f"p{period}"] = r.false_rate(6 + period, lambda g, n, t, p=period: moves_periodic(n, t, p))
        worst = max(res.values(), key=lambda x: x["ub95"])
        power = power_row(r, lambda g, p, s, x=edges[2]: planted_moves(g, p, world.c, x), 2, 400, power_rounds, power_n)
        out.append({"kappa": kappa, "m": r.fp.m, "worstUb95": worst["ub95"], "worstRate": worst["rate"], "plantedN90": power["n90"], "plantedShare": power["share"], "g": power["g"]})
        print(f"  kappa {kappa}: worst ub95 {worst['ub95']:.4f}, planted n90 {power['n90']}, share {power['share']:.3f}", flush=True)
    return out


def fmt_pct(x):
    return f"{100 * x:.2f}%"


def render(results, alpha, quick, elapsed):
    lines = ["# Referee validation", ""]
    mode = "Quick run" if quick else "Full run"
    lines += [
        f"{mode}. Generated by `engine/sim/attacks.py` in {elapsed / 60:.1f} minutes. Reproduce with `make validate`.",
        "",
        "**Data:** recorded Binance 1 s prices (public archive, see `config/SOURCES.md`). This is real market data but not Pyth's own feed. A Pyth sample is still to be added.",
        "",
        "**Reading the seeds:** every seed draws a new career start and new coin flips, but careers share one month of market history, so market paths are not fully independent between seeds.",
        "",
    ]
    for feed in results["feeds"]:
        lines += [f"## {feed['slug'].upper()}", "", f"Fitted on the fit days only: storm line C = {feed['c']:.3f}, single-signal threshold {feed['theta']:.3f}, forecast weights {[round(x, 3) for x in feed['beta']]}, forecast median {feed['forecastMedian']:.3f}.", ""]
        lines += [f"### False-Skilled rate, target at most {fmt_pct(alpha)} at the 95% upper bound", "", "| # | Attack | Certified | Rate | 95% upper bound | Result |", "| --- | --- | --- | --- | --- | --- |"]
        for key, row in feed["attacks"].items():
            if key.startswith("5-") and key != "5-long":
                continue
            ok = "PASS" if row["ub95"] <= alpha else "**FAIL**"
            lines.append(f"| {key} | {row['label']} | {row['hits']}/{row['n']} | {fmt_pct(row['rate'])} | {fmt_pct(row['ub95'])} | {ok} |")
        lines += ["", "### Power", "", "Rounds until the given share of careers is certified. A dash means that share was not reached within the career length.", "", "| Strategy | K | Certified | N50 | N90 | N99 | Measured g |", "| --- | --- | --- | --- | --- | --- | --- |"]
        for row in feed["power"]:
            d = lambda v: "–" if v is None else str(v)
            lines.append(f"| {row['strategy']} | {row['k']} | {fmt_pct(row['share'])} | {d(row['n50'])} | {d(row['n90'])} | {d(row['n99'])} | {row['g']:.5f} |")
        lines += ["", "### Lapse detector", "", "| Case | Certified | Of those, lapsed | Median rounds to lapse after the change |", "| --- | --- | --- | --- |"]
        for row in feed["lapse"]:
            med = "–" if row["medianAfterSwitch"] is None else row["medianAfterSwitch"]
            lines.append(f"| {row['label']} | {fmt_pct(row['certified'])} | {fmt_pct(row['lapsed'])} | {med} |")
        lines += ["", "### ONS against the plug-in bet, same seeds, K = 2", "", "| Planted edge | Bet | Certified | N50 | N90 |", "| --- | --- | --- | --- | --- |"]
        for row in feed["betCompare"]:
            d = lambda v: "–" if v is None else str(v)
            lines.append(f"| {row['edge']:.0%} | {row['bet']} | {fmt_pct(row['share'])} | {d(row['n50'])} | {d(row['n90'])} |")
        if feed.get("kappa"):
            lines += ["", "### κ calibration", "", "| κ | M | Worst drift attack, 95% upper bound | Planted-edge N90 | Certified | g |", "| --- | --- | --- | --- | --- | --- |"]
            for row in feed["kappa"]:
                d = "–" if row["plantedN90"] is None else row["plantedN90"]
                lines.append(f"| {row['kappa']} | {row['m']:.0f} | {fmt_pct(row['worstUb95'])} | {d} | {fmt_pct(row['plantedShare'])} | {row['g']:.5f} |")
        lines.append("")
    lines += [
        "## Attacks checked by tests, not by replay",
        "",
        "| # | Attack | Result | Where |",
        "| --- | --- | --- | --- |",
        "| 9 | Match-fixing opponent | The referee reads no opponent data, so the verdict cannot change | `test_opponent_has_no_effect_on_a_fighters_state`, `test_opponentDoesNotChangeAFightersState` |",
        "| 10 | Void rounds | Void rounds never reach the referee; state is unchanged | `test_void_round_is_not_recorded_and_leaves_state_unchanged` |",
        "| 11 | Overdrive and Read | The referee has no input for them | `test_overdrive_and_read_have_no_entry_point` |",
        "| 12 | Copycat | Moves are hidden until both commits are anchored, so copying before commit is not possible | DuelArena reveal rules |",
        "| 13 | Borrowed World ID | A disclosed limit: one person using another's ID gets a second family. A correlated-family flag marks families whose moves agree | `docs/scoring-rule.md` |",
        "| 14 | Sigma steering | The referee sets its own z scale from raw returns, and has no sigma input | `test_referee_ignores_duel_sigma` |",
        "",
    ]
    return "\n".join(lines)


def a_elapsed(feeds):
    return max((f.get("elapsedS", 0) for f in feeds), default=0)


def merge(stem):
    """Combines per-feed results written by parallel runs."""
    found = sorted(REPORTS.glob(f"{stem}-*.json"))
    return [json.loads(p.read_text())["feeds"][0] for p in found]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--feeds", default=None, help="comma-separated slugs")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--merge", action="store_true", help="combine per-feed runs into one report")
    a = ap.parse_args()
    if a.merge:
        stem = "referee-validation"
        feeds = merge(stem)
        alpha = 1 / load_params().alpha_inv
        results = {"seeds": feeds and load_params().raw["validation"]["seeds"], "quick": False, "feeds": feeds}
        (REPORTS / f"{stem}.json").write_text(json.dumps(results, indent=1) + "\n")
        (REPORTS / f"{stem}.md").write_text(render(results, alpha, False, a_elapsed(feeds)) + "\n")
        return
    params = load_params()
    raw = params.raw
    v = raw["validation"]
    alpha = 1 / params.alpha_inv
    seeds = v["quickSeeds"] if a.quick else v["seeds"]
    candidates = max(v["optimiserCandidates"] // 5, 50) if a.quick else v["optimiserCandidates"]
    want = a.feeds.split(",") if a.feeds else [raw["feeds"]["entries"][n]["slug"] for n in raw["feeds"]["order"]]
    t0 = time.time()
    results = {"seeds": seeds, "quick": a.quick, "feeds": []}
    edges = [e / 100 for e in v["plantedEdgesPct"]]
    power_n = max(seeds // 5, 200)
    for name in raw["feeds"]["order"]:
        e = raw["feeds"]["entries"][name]
        if e["slug"] not in want:
            continue
        world = World(params, e["slug"], e["id"])
        print(f"{e['slug']}: C {world.c:.3f}, theta {world.theta:.3f}", flush=True)
        feed = {"slug": e["slug"], "c": world.c, "theta": world.theta, "beta": world.beta.tolist(), "forecastMedian": world.forecast_median}
        if a.calibrate:
            feed["kappa"] = calibrate_kappa(world, seeds, v["roundsPerCareer"], [x / 100 for x in v["kappaGridPct"]], edges, v["powerRounds"], power_n)
        run = Runner(world, seeds, v["roundsPerCareer"])
        feed["attacks"] = attack_table(run, candidates, v["staggeredFamilySize"])
        for key, row in feed["attacks"].items():
            print(f"  {key}: {row['hits']}/{row['n']} ub95 {row['ub95']:.4f}", flush=True)
        feed["power"], feed["betCompare"] = power_table(run, edges, v["powerRounds"], power_n)
        feed["lapse"] = lapse_table(run, edges[-1], v["powerRounds"], power_n)
        for row in feed["power"]:
            print(f"  {row['strategy']} k={row['k']}: {row['share']:.3f} n50 {row['n50']} n90 {row['n90']} n99 {row['n99']} g {row['g']:.5f}", flush=True)
        results["feeds"].append(feed)
    elapsed = time.time() - t0
    REPORTS.mkdir(parents=True, exist_ok=True)
    results["feeds"][0]["elapsedS"] = elapsed
    stem = "referee-validation-quick" if a.quick else "referee-validation"
    if a.feeds and not a.quick:
        stem = f"{stem}-{a.feeds.replace(',', '_')}"
    (REPORTS / f"{stem}.json").write_text(json.dumps(results, indent=1) + "\n")
    if not (a.feeds and not a.quick):
        (REPORTS / f"{stem}.md").write_text(render(results, alpha, a.quick, elapsed) + "\n")
    print(f"done in {elapsed / 60:.1f} min")


if __name__ == "__main__":
    main()
