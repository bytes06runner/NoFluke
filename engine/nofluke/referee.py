"""Luck referee v3: the integer reference. TypeScript and Solidity must match it bit for bit.

See docs/scoring-rule.md for the maths and why it is valid.
"""
from dataclasses import astuple, dataclass, field
from math import isqrt

WAD = 10**18
UP, DOWN, GUARD, BURST = 0, 1, 2, 3
_MOD = 1 << 256
_SIGN = 1 << 255


def tdiv(a: int, b: int) -> int:
    """Integer division truncating toward zero, as Solidity does."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def clip(x: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, x))


def _s(x: int) -> int:
    """Reads a 256-bit word as signed."""
    x %= _MOD
    return x - _MOD if x >= _SIGN else x


def _sar(n: int, x: int) -> int:
    return _s(x) >> n


def _byte(i: int, word: int) -> int:
    return (word >> (8 * (31 - i))) & 0xFF


def ln_wad(x: int) -> int:
    """A port of Solady FixedPointMathLib.lnWad, with EVM word wrapping, so results match exactly."""
    if x <= 0:
        raise ValueError("lnWad undefined")
    r = (1 << 7) * (x > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    r |= (1 << 6) * ((x >> r) > 0xFFFFFFFFFFFFFFFF)
    r |= (1 << 5) * ((x >> r) > 0xFFFFFFFF)
    r |= (1 << 4) * ((x >> r) > 0xFFFF)
    r |= (1 << 3) * ((x >> r) > 0xFF)
    table = 0xF8F9F9FAF9FDFAFBF9FDFCFDFAFBFCFEF9FAFDFAFCFCFBFEFAFAFCFBFFFFFFFF  # lint-hardcode-ok: Solady lookup table
    idx = (0x8421084210842108CC6318C6DB6D54BE >> (x >> r)) & 0x1F if (x >> r) < 256 else 0
    r ^= _byte(idx, table)
    x = (((x << r) % _MOD) >> 159)

    p = (_sar(96, (3273285459638523848632254066296 + x) * x) + 24828157081833163892658089445524)
    p = _sar(96, p * x) + 43456485725739037958740375743393
    p = _sar(96, p * x) - 11111509109440967052023855526967
    p = _sar(96, p * x) - 45023709667254063763336534515857
    p = _sar(96, p * x) - 14706773417378608786704636184526
    p = _s(p * x - (795164235651350426258249787498 << 96))

    q = 5573035233440673466300451813936 + x
    q = 71694874799317883764090561454958 + _sar(96, x * q)
    q = 283447036172924575727196451306956 + _sar(96, x * q)
    q = 401686690394027663651624208769553 + _sar(96, x * q)
    q = 204048457590392012362485061816622 + _sar(96, x * q)
    q = 31853899698501571402653359427138 + _sar(96, x * q)
    q = 909429971244387300277376558375 + _sar(96, x * q)

    p = tdiv(p, _s(q))
    p = _s(1677202110996718588342820967067443963516166 * p)
    p = _s(16597577552685614221487285958193947469193820559219878177908093499208371 * (159 - r) + p)
    p = _s(600920179829731861736702779321621459595472258049074101567377883020018308 + p)
    return _sar(174, p)


@dataclass
class FighterState:
    n: list = field(default_factory=lambda: [0, 0, 0, 0])
    n_short: list = field(default_factory=lambda: [0, 0, 0, 0])
    logW: int = 0
    lambda_: int = 0
    A: int = WAD
    logL: int = 0
    rounds: int = 0
    k_at_cert: int = 0
    lapsed: bool = False


@dataclass
class FeedState:
    mean_z: int = 0
    mean_abs: int = 0
    mean_z_short: int = 0
    mean_abs_short: int = 0
    var_return: int = 0
    count: int = 0
    last_t: int = 0

    def snapshot(self):
        return astuple(self)


@dataclass(frozen=True)
class Verdict:
    skilled: bool
    lapsed: bool
    logW: int
    lnBar: int
    rounds: int
    lambda_: int
    k_at_cert: int


class Referee:
    def __init__(self, params):
        self.p = params
        self.fighters = {}
        self.feeds = {}
        self._gamma = WAD - WAD // params.habit_horizon
        self._gamma_short = WAD - WAD // params.habit_short_horizon
        self._ln_a = ln_wad(params.lapse_a * WAD)
        self._sigma_floor = params.sigma_min_ppm * 10**12

    def fighter(self, addr) -> FighterState:
        return self.fighters.setdefault(addr, FighterState())

    def feed(self, feed_id) -> FeedState:
        if feed_id not in self.feeds:
            sigma = self.p.sigma_init_ppm[feed_id] * 10**12
            self.feeds[feed_id] = FeedState(var_return=sigma * sigma // WAD)
        return self.feeds[feed_id]

    def snapshot(self):
        return (
            {k: astuple(v) for k, v in self.fighters.items()},
            {k: astuple(v) for k, v in self.feeds.items()},
        )

    def sigma_wad(self, feed_id) -> int:
        return max(isqrt(self.feed(feed_id).var_return * WAD), self._sigma_floor)

    def ln_bar(self, k: int) -> int:
        return ln_wad(k * (k + 1) * self.p.alpha_inv * WAD)

    def _means(self, mean_z: int, mean_abs: int, c: int) -> list:
        k, d = self.p.payoff_per_z, self.p.delta
        return [
            clip(k * mean_z, -d, d),
            clip(-k * mean_z, -d, d),
            clip(k * (c - mean_abs), -d, d),
            clip(k * (mean_abs - c), -d, d),
        ]

    def _payoffs(self, z: int, c: int) -> list:
        k = self.p.payoff_per_z
        a = abs(z)
        return [k * z, -k * z, k * (c - a), k * (a - c)]

    def drift_d(self, s: FighterState) -> int:
        """d_t: the L1 distance between short and long habit frequencies."""
        nl, ns = sum(s.n), sum(s.n_short)
        total = 0
        for m in range(4):
            fl = tdiv((s.n[m] + WAD) * WAD, nl + 4 * WAD)
            fs = tdiv((s.n_short[m] + WAD) * WAD, ns + 4 * WAD)
            total += abs(fs - fl)
        return total

    def _drift_e(self, f: FeedState, c: int) -> int:
        """e_t: the largest gap between short and long public move averages."""
        lng = self._means(f.mean_z, f.mean_abs, c)
        sht = self._means(f.mean_z_short, f.mean_abs_short, c)
        return max(abs(a - b) for a, b in zip(sht, lng))

    def drift_penalty(self, s: FighterState, f: FeedState, c: int) -> int:
        return tdiv(tdiv(self.p.kappa * self.drift_d(s), WAD) * self._drift_e(f, c), WAD)

    def excess_v(self, s: FighterState, f: FeedState, move: int, z: int, c: int) -> int:
        zc = clip(z, -self.p.z_clip, self.p.z_clip)
        mu = self._means(f.mean_z, f.mean_abs, c)
        centred = [a - b for a, b in zip(self._payoffs(zc, c), mu)]
        baseline = tdiv(sum((s.n[m] + WAD) * centred[m] for m in range(4)), sum(s.n) + 4 * WAD)
        x = centred[move] - baseline - self.drift_penalty(s, f, c)
        return clip(tdiv(x * WAD, self.p.m), -WAD, WAD)

    def _bet(self, s: FighterState, v: int, k: int) -> None:
        p = self.p
        term = WAD + tdiv(s.lambda_ * v, WAD)
        s.logW += ln_wad(term)
        g = tdiv(v * WAD, term)
        s.A += tdiv(g * g, WAD)
        s.lambda_ = clip(s.lambda_ + tdiv(tdiv(p.ons_beta * g, WAD) * WAD, s.A), 0, p.lambda_max)
        s.rounds += 1
        if s.k_at_cert == 0:
            if s.logW >= self.ln_bar(k):
                s.k_at_cert = k
        elif not s.lapsed:
            s.logL = max(s.logL, 0) + ln_wad(WAD - tdiv(p.lapse_lambda * (v - p.lapse_edge_floor), WAD))
            if s.logL >= self._ln_a:
                s.lapsed = True

    def _update(self, addr, move: int, z: int, c: int, f: FeedState, k: int) -> None:
        s = self.fighter(addr)
        self._bet(s, self.excess_v(s, f, move, z, c), k)
        for m in range(4):
            hit = WAD if m == move else 0
            s.n[m] = s.n[m] * self._gamma // WAD + hit
            s.n_short[m] = s.n_short[m] * self._gamma_short // WAD + hit

    def _update_feed(self, f: FeedState, t: int, r: int, z: int) -> None:
        if f.count > 0 and t < f.last_t + self.p.tape_s:
            return
        zc = clip(z, -self.p.z_clip, self.p.z_clip)
        a = abs(zc)
        f.count += 1
        long_h = min(f.count, self.p.mean_horizon)
        short_h = min(f.count, self.p.mean_short_horizon)
        f.mean_z += tdiv(zc - f.mean_z, long_h)
        f.mean_abs += tdiv(a - f.mean_abs, long_h)
        f.mean_z_short += tdiv(zc - f.mean_z_short, short_h)
        f.mean_abs_short += tdiv(a - f.mean_abs_short, short_h)
        f.var_return += tdiv(r * r // WAD - f.var_return, self.p.sigma_horizon)
        f.last_t = t

    def record_round(self, feed_id, t, p0, p1, c, fighter_a, move_a, k_a, fighter_b, move_b, k_b) -> None:
        """One scored, non-void round. Both fighters use the feed state from before this round."""
        f = self.feed(feed_id)
        r = tdiv((p1 - p0) * WAD, p0)
        z = tdiv(r * WAD, self.sigma_wad(feed_id))
        self._update(fighter_a, move_a, z, c, f, k_a)
        self._update(fighter_b, move_b, z, c, f, k_b)
        self._update_feed(f, t, r, z)

    def record_forfeit(self, addr, k: int) -> None:
        """A missed or unrevealed round counts as v = -1. Habits and feed state do not change."""
        self._bet(self.fighter(addr), -WAD, k)

    def verdict_of(self, addr, k: int) -> Verdict:
        s = self.fighter(addr)
        return Verdict(s.k_at_cert > 0, s.lapsed, s.logW, self.ln_bar(k), s.rounds, s.lambda_, s.k_at_cert)
