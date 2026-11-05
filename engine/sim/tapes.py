"""Builds rounds from recorded 1 s prices: real returns, and the storm signal a fighter could see before committing."""
from dataclasses import dataclass
from pathlib import Path

import numpy as np

DATA = Path(__file__).resolve().parents[1] / "data"


@dataclass
class Tape:
    """Prices on a gap-free 1 s grid. Missing seconds carry the last price."""

    slug: str
    close: np.ndarray
    storm_raw: np.ndarray  # mean absolute 1 s log return over the look-back window, ending at each second


def load_tape(slug: str, lookback_s: int, min_samples: int) -> Tape:
    d = np.load(DATA / f"{slug}.npz")
    t, close = d["t"], d["close"]
    order = np.argsort(t)
    t, close = t[order], close[order]
    start, end = t[0], t[-1]
    grid = np.full(end - start + 1, np.nan)
    grid[t - start] = close
    seen = ~np.isnan(grid)
    filled = grid.copy()
    last = np.maximum.accumulate(np.where(seen, np.arange(len(grid)), 0))
    filled = grid[last]
    log_ret = np.abs(np.diff(np.log(filled), prepend=np.log(filled[0])))
    csum = np.cumsum(log_ret)
    csamples = np.cumsum(seen.astype(np.int64))
    storm = np.full(len(filled), np.nan)
    window_sum = csum[lookback_s:] - csum[:-lookback_s]
    window_seen = csamples[lookback_s:] - csamples[:-lookback_s]
    storm[lookback_s:] = np.where(window_seen >= min_samples, window_sum / lookback_s, np.nan)
    return Tape(slug, filled, storm)


def sample_careers(tape: Tape, rng: np.random.Generator, n: int, rounds: int, tape_s: int, per_match: int, gap_s: int, lead_s: int, lo: float = 0.0, hi: float = 1.0):
    """Random career start times within a share of the data. Rounds are contiguous within a match, with a gap between matches."""
    offsets = np.arange(rounds)
    # Each completed match adds a gap, because creating, joining and settling take real time.
    seconds = offsets * tape_s + (offsets // per_match) * gap_s
    span = seconds[-1] + tape_s
    size = len(tape.close)
    first = int(size * lo) + lead_s
    last = int(size * hi) - span - 1
    if last <= first:
        raise ValueError("not enough data for this career length")
    starts = rng.integers(first, last, size=n)
    t0 = starts[:, None] + seconds[None, :]
    p0 = tape.close[t0]
    p1 = tape.close[t0 + tape_s]
    returns = (p1 - p0) / p0
    storm = tape.storm_raw[t0 - lead_s] * np.sqrt(tape_s)
    return returns, np.nan_to_num(storm, nan=0.0), t0


def plain_returns(tape: Tape, tape_s: int, lo: float, hi: float) -> np.ndarray:
    a, b = int(len(tape.close) * lo), int(len(tape.close) * hi)
    p = tape.close[a:b:tape_s]
    return np.diff(p) / p[:-1]
