"""The fast simulator must agree with the integer referee, so its results stand for the contract."""
import numpy as np

from nofluke.params import load_params
from nofluke.referee import Referee, WAD
from sim.fast import FastParams, feed_paths, run_career

P = load_params()
FEED = P.feed_ids[0]
C_INT = P.storm_c[FEED]
SIGMA_INIT = P.sigma_init_ppm[FEED] * 1e-6
P0 = 10**12


def integer_run(prices, moves, k, forfeits=None):
    ref = Referee(P)
    t = 1_800_000_000
    out = []
    for i, p1 in enumerate(prices):
        if forfeits is not None and forfeits[i]:
            ref.record_forfeit("a", k)
        else:
            ref.record_round(FEED, t, P0, int(p1), C_INT, "a", int(moves[i]), k, "b", int((moves[i] + 1) % 4), k)
            t += P.tape_s
        out.append(ref.fighter("a").logW / WAD)
    return ref, out


def fast_run(rets, moves, k, forfeit=None):
    fp = FastParams.of(P)
    paths = feed_paths(fp, rets[None, :], C_INT / WAD, SIGMA_INIT)
    return run_career(fp, paths, moves[None, :], k, C_INT / WAD, forfeit=None if forfeit is None else forfeit[None, :])


def test_fast_matches_integer_on_logw():
    rng = np.random.default_rng(1)
    n = 800
    prices = (P0 * (1 + rng.normal(0, 2e-4, n))).astype(np.int64)
    rets = (prices - P0) / P0
    moves = rng.integers(0, 4, n)
    ref, _ = integer_run(prices, moves, 2)
    fast = fast_run(rets, moves, 2)
    assert abs(fast.log_w[0] - ref.fighter("a").logW / WAD) < 1e-6


def test_fast_matches_integer_when_certifying():
    rng = np.random.default_rng(2)
    n = 1000
    prices = (P0 * (1 + rng.normal(0, 2e-4, n))).astype(np.int64)
    rets = (prices - P0) / P0
    moves = np.where(rets > 0, 0, 1)
    moves = np.where(rng.random(n) < 0.5, moves, rng.integers(0, 4, n))
    ref, _ = integer_run(prices, moves, 2)
    fast = fast_run(rets, moves, 2)
    assert abs(fast.log_w[0] - ref.fighter("a").logW / WAD) < 1e-6
    assert (fast.crossed_at[0] >= 0) == (ref.fighter("a").k_at_cert > 0)
    assert (fast.lapsed_at[0] >= 0) == ref.fighter("a").lapsed


def test_float_and_integer_agree_on_forfeits_when_the_feed_keeps_moving():
    rng = np.random.default_rng(3)
    n = 300
    prices = (P0 * (1 + rng.normal(0, 2e-4, n))).astype(np.int64)
    rets = (prices - P0) / P0
    moves = np.where(rets > 0, 0, 1)
    # A forfeit round still updates the feed through the opponent's other duels in real life. Here: compare only v = -1 effect.
    ref = Referee(P)
    t = 1_800_000_000
    forfeit = np.zeros(n, bool)
    forfeit[10::7] = True
    for i in range(n):
        ref.record_round(FEED, t, P0, int(prices[i]), C_INT, "x", int(moves[i]), 2, "y", 0, 2) if not forfeit[i] else ref.record_round(FEED, t, P0, int(prices[i]), C_INT, "y", 0, 2, "z", 1, 2)
        if forfeit[i]:
            ref.record_forfeit("x", 2)
        t += P.tape_s
    fast = fast_run(rets, moves, 2, forfeit)
    assert abs(fast.log_w[0] - ref.fighter("x").logW / WAD) < 1e-6
