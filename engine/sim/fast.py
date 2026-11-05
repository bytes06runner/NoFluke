"""Vectorised float version of the referee, for 10,000-seed replays.

tests/test_sim.py checks it against the integer reference, so a result here stands for the contract's behaviour.
"""
from dataclasses import dataclass

import numpy as np

WAD = 1e18
UP, DOWN, GUARD, BURST = 0, 1, 2, 3


@dataclass(frozen=True)
class FastParams:
    alpha_inv: float
    z_clip: float
    delta: float
    payoff_per_z: float
    habit_horizon: int
    habit_short_horizon: int
    mean_horizon: int
    mean_short_horizon: int
    sigma_horizon: int
    kappa: float
    m: float
    lambda_max: float
    ons_beta: float
    lapse_lambda: float
    lapse_a: float
    lapse_edge_floor: float
    sigma_floor: float
    a0: float = 1.0

    @staticmethod
    def of(p) -> "FastParams":
        return FastParams(
            alpha_inv=float(p.alpha_inv),
            z_clip=p.z_clip / WAD,
            delta=p.delta / WAD,
            payoff_per_z=float(p.payoff_per_z),
            habit_horizon=p.habit_horizon,
            habit_short_horizon=p.habit_short_horizon,
            mean_horizon=p.mean_horizon,
            mean_short_horizon=p.mean_short_horizon,
            sigma_horizon=p.sigma_horizon,
            kappa=p.kappa / WAD,
            m=p.m / WAD,
            lambda_max=p.lambda_max / WAD,
            ons_beta=p.ons_beta / WAD,
            a0=p.ons_a0 / WAD,
            lapse_lambda=p.lapse_lambda / WAD,
            lapse_a=float(p.lapse_a),
            lapse_edge_floor=p.lapse_edge_floor / WAD,
            sigma_floor=p.sigma_min_ppm * 1e-6,
        )


@dataclass
class FeedPaths:
    """Per career and round: the referee's z and the public move averages from before that round."""

    r: np.ndarray
    z: np.ndarray
    mu: np.ndarray
    mu_short: np.ndarray
    sigma: np.ndarray


def _means(k, mean_z, mean_abs, c, delta):
    return np.clip(np.stack([k * mean_z, -k * mean_z, k * (c - mean_abs), k * (mean_abs - c)], axis=-1), -delta, delta)


def feed_paths(p: FastParams, returns: np.ndarray, c: float, sigma_init: float, update_mask=None) -> FeedPaths:
    """Runs the shared feed state along each career. `update_mask` false means that round does not update the feed."""
    n, t = returns.shape
    var = np.full(n, sigma_init**2)
    mz = np.zeros(n)
    ma = np.zeros(n)
    mzs = np.zeros(n)
    mas = np.zeros(n)
    count = np.zeros(n)
    z_out = np.empty((n, t))
    sig_out = np.empty((n, t))
    mu = np.empty((n, t, 4))
    mus = np.empty((n, t, 4))
    k = p.payoff_per_z
    for i in range(t):
        sigma = np.maximum(np.sqrt(var), p.sigma_floor)
        r = returns[:, i]
        z = r / sigma
        z_out[:, i] = z
        sig_out[:, i] = sigma
        mu[:, i] = _means(k, mz, ma, c, p.delta)
        mus[:, i] = _means(k, mzs, mas, c, p.delta)
        on = np.ones(n, bool) if update_mask is None else update_mask[:, i]
        zc = np.clip(z, -p.z_clip, p.z_clip)
        a = np.abs(zc)
        count = count + on
        lh = np.minimum(np.maximum(count, 1), p.mean_horizon)
        sh = np.minimum(np.maximum(count, 1), p.mean_short_horizon)
        mz = mz + on * (zc - mz) / lh
        ma = ma + on * (a - ma) / lh
        mzs = mzs + on * (zc - mzs) / sh
        mas = mas + on * (a - mas) / sh
        var = var + on * (r * r - var) / p.sigma_horizon
    return FeedPaths(returns, z_out, mu, mus, sig_out)


@dataclass
class Career:
    crossed_at: np.ndarray  # first round a fighter crossed its bar, or -1
    log_w: np.ndarray
    peak_gap: np.ndarray
    v_mean: np.ndarray
    v2_mean: np.ndarray
    lapsed_at: np.ndarray


def run_career(p: FastParams, paths: FeedPaths, moves: np.ndarray, k, c: float, forfeit=None, bet: str = "ons", start=None) -> Career:
    """One fighter per career. moves is (n, t). k is a scalar or (n, t). forfeit marks rounds that count as v = -1."""
    n, t = moves.shape
    counts = np.zeros((n, 4))
    counts_s = np.zeros((n, 4))
    log_w = np.zeros(n)
    lam = np.zeros(n)
    A = np.full(n, p.a0)
    log_l = np.zeros(n)
    crossed_at = np.full(n, -1)
    lapsed_at = np.full(n, -1)
    peak = np.full(n, -np.inf)
    gamma = 1 - 1 / p.habit_horizon
    gamma_s = 1 - 1 / p.habit_short_horizon
    k_arr = np.broadcast_to(np.asarray(k, dtype=float), (n, t)) if np.ndim(k) else None
    bar_const = np.log(float(k) * (float(k) + 1) * p.alpha_inv) if k_arr is None else None
    pz = p.payoff_per_z
    sum_v = np.zeros(n)
    sum_v2 = np.zeros(n)
    played = np.zeros(n)
    s1 = np.zeros(n)
    s2 = np.zeros(n)
    idx = np.arange(n)
    active = None
    for i in range(t):
        if start is not None:
            active = i >= start
        zc = np.clip(paths.z[:, i], -p.z_clip, p.z_clip)
        a = np.abs(zc)
        pay = np.stack([pz * zc, -pz * zc, pz * (c - a), pz * (a - c)], axis=1)
        centred = pay - paths.mu[:, i]
        total = counts.sum(1)
        base = ((counts + 1) * centred).sum(1) / (total + 4)
        fl = (counts + 1) / (total[:, None] + 4)
        fs = (counts_s + 1) / (counts_s.sum(1)[:, None] + 4)
        d = np.abs(fs - fl).sum(1)
        e = np.abs(paths.mu_short[:, i] - paths.mu[:, i]).max(1)
        x = centred[idx, moves[:, i]] - base - p.kappa * d * e
        v = np.clip(x / p.m, -1, 1)
        if forfeit is not None:
            v = np.where(forfeit[:, i], -1.0, v)
        if active is not None:
            v = np.where(active, v, 0.0)
        term = 1 + lam * v
        log_w = log_w + np.log(term)
        if bet == "ons":
            g = v / term
            A = A + g * g
            lam = np.clip(lam + p.ons_beta * g / A, 0, p.lambda_max)
        else:
            # The plug-in rule: mean over variance from past rounds, with a warm-up, on the same seeds.
            s1 += v
            s2 += v * v
            count = played + 1
            var_est = np.maximum(s2 / count - (s1 / count) ** 2, 1e-3)
            lam = np.where(count >= 20, np.clip((s1 / count) / var_est, 0, p.lambda_max), 0.0)
        bar = np.log(k_arr[:, i] * (k_arr[:, i] + 1) * p.alpha_inv) if k_arr is not None else bar_const
        gap = log_w - bar
        peak = np.maximum(peak, gap)
        newly = (crossed_at < 0) & (gap >= 0)
        crossed_at = np.where(newly, i, crossed_at)
        cert = (crossed_at >= 0) & (~newly) & (lapsed_at < 0)
        log_l = np.where(cert, np.maximum(log_l, 0) + np.log(1 - p.lapse_lambda * (v - p.lapse_edge_floor)), log_l)
        lapsed_at = np.where(cert & (log_l >= np.log(p.lapse_a)), i, lapsed_at)
        hit = np.zeros((n, 4))
        hit[idx, moves[:, i]] = 1.0
        if forfeit is not None:
            hit = hit * (~forfeit[:, i])[:, None]
            gamma_f = np.where(forfeit[:, i], 1.0, gamma)[:, None]
            gamma_fs = np.where(forfeit[:, i], 1.0, gamma_s)[:, None]
        else:
            gamma_f, gamma_fs = gamma, gamma_s
        if active is not None:
            hit = hit * active[:, None]
            gamma_f = np.where(active, gamma_f if np.ndim(gamma_f) == 0 else gamma_f[:, 0], 1.0)[:, None]
            gamma_fs = np.where(active, gamma_fs if np.ndim(gamma_fs) == 0 else gamma_fs[:, 0], 1.0)[:, None]
        counts = counts * gamma_f + hit
        counts_s = counts_s * gamma_fs + hit
        step = np.ones(n) if active is None else active.astype(float)
        sum_v += v * step
        sum_v2 += v * v * step
        played += step
    return Career(crossed_at, log_w, peak, sum_v / np.maximum(played, 1), sum_v2 / np.maximum(played, 1), lapsed_at)
