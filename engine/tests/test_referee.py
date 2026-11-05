"""Referee v3 rules. Each test names the rule it pins down."""
import math
import random

import pytest

from nofluke.params import load_params
from nofluke.referee import BURST, DOWN, GUARD, UP, Referee, WAD, ln_wad, tdiv

P = load_params()
FEED = P.feed_ids[0]
C = P.storm_c[FEED]
P0 = 10_000_000_000


def price_for_z(ref, z_float):
    """p1 such that the referee's zRef for this round is about z_float."""
    sigma = ref.sigma_wad(FEED) / WAD
    return int(P0 * (1 + z_float * sigma))


def play(ref, fighter, move, z=0.5, k=2, t=None, other="opp", other_move=GUARD):
    t = ref.feed(FEED).last_t + P.tape_s if t is None else t
    ref.record_round(FEED, t, P0, price_for_z(ref, z), C, fighter, move, k, other, other_move, k)
    return t


def test_tdiv_truncates_toward_zero():
    assert tdiv(-7, 2) == -3
    assert tdiv(7, -2) == -3
    assert tdiv(-7, -2) == 3
    assert tdiv(7, 2) == 3


@pytest.mark.parametrize("x", [1, 10**6, WAD // 3, WAD, WAD + 1, 2 * WAD, 3 * WAD, 600 * WAD, 10**30, 10**40])
def test_ln_wad_is_accurate(x):
    assert abs(ln_wad(x) / WAD - math.log(x / WAD)) < 1e-9


def test_ln_wad_rejects_non_positive():
    with pytest.raises(ValueError):
        ln_wad(0)
    with pytest.raises(ValueError):
        ln_wad(-1)


def test_ons_beta_constant_matches_its_definition():
    assert abs(P.ons_beta / WAD - 2 / (2 - math.log(3))) < 1e-15


def test_new_fighter_starts_with_no_evidence():
    s = Referee(P).verdict_of("a", 1)
    assert s.logW == 0 and s.rounds == 0 and s.lambda_ == 0 and s.k_at_cert == 0 and not s.skilled and not s.lapsed


def test_first_round_bet_is_zero_so_wealth_does_not_move():
    ref = Referee(P)
    play(ref, "a", UP, z=1.0)
    assert ref.fighter("a").logW == 0
    assert ref.fighter("a").rounds == 1


def test_lambda_stays_within_bounds_at_both_clamps():
    ref = Referee(P)
    for _ in range(200):
        play(ref, "a", DOWN, z=2.0)
    assert ref.fighter("a").lambda_ == 0 or ref.fighter("a").lambda_ < WAD // 100
    ref = Referee(P)
    for i in range(600):
        z = 2.0 if i % 2 else -2.0
        play(ref, "b", UP if z > 0 else DOWN, z=z)
    assert ref.fighter("b").lambda_ <= P.lambda_max
    assert ref.fighter("b").lambda_ > 0


def test_excess_is_never_clipped():
    # |x'| <= M across random z, habits and means: the clip on v must not bind.
    rng = random.Random(1)
    ref = Referee(P)
    for _ in range(3000):
        move = rng.randrange(4)
        v = ref.excess_v(ref.fighter("a"), ref.feed(FEED), move, rng.uniform(-40, 40) * WAD, C)
        assert abs(v) <= WAD
        play(ref, "a", move, z=rng.uniform(-6, 6))


def test_void_round_is_not_recorded_and_leaves_state_unchanged():
    # A void round never reaches the referee: there is no entry point for it, and state is untouched.
    ref = Referee(P)
    play(ref, "a", UP)
    before = ref.snapshot()
    assert ref.snapshot() == before
    assert not hasattr(ref, "record_void")


def test_overdrive_and_read_have_no_entry_point():
    import inspect

    params = inspect.signature(Referee.record_round).parameters
    assert not any("read" in n or "overdrive" in n for n in params)


def test_forfeit_counts_as_full_loss_and_keeps_habits():
    ref = Referee(P)
    for i in range(200):
        z = 2.0 if i % 2 else -2.0
        play(ref, "a", UP if z > 0 else DOWN, z=z)
    s = ref.fighter("a")
    n_before, log_w, lam, rounds = list(s.n), s.logW, s.lambda_, s.rounds
    assert lam > 0
    ref.record_forfeit("a", 2)
    s = ref.fighter("a")
    assert s.rounds == rounds + 1
    assert s.n == n_before
    assert s.logW == log_w + ln_wad(WAD - lam)
    assert s.logW < log_w


def test_selective_reveal_never_certifies():
    # Rule 8: reveal only the winners, forfeit the rest. Half the rounds lose everything the bet allows.
    rng = random.Random(7)
    ref = Referee(P)
    for _ in range(3000):
        z = rng.gauss(0, 1)
        guess_right = rng.random() < 0.5
        if guess_right:
            play(ref, "a", UP if z > 0 else DOWN, z=z)
        else:
            ref.record_forfeit("a", 2)
    assert not ref.verdict_of("a", 2).skilled


def test_opponent_has_no_effect_on_a_fighters_state():
    a, b = Referee(P), Referee(P)
    rng = random.Random(3)
    for _ in range(100):
        z, m = rng.gauss(0, 1), rng.randrange(4)
        t = a.feed(FEED).last_t + P.tape_s
        p1 = price_for_z(a, z)
        a.record_round(FEED, t, P0, p1, C, "f", m, 2, "x", UP, 2)
        b.record_round(FEED, t, P0, p1, C, "f", m, 2, "y", rng.randrange(4), 5)
    assert a.fighter("f") == b.fighter("f")


def test_referee_ignores_duel_sigma():
    # record_round takes raw prices only, so a creator's sigmaRef cannot steer the referee's z.
    import inspect

    assert not any("sigma" in n for n in inspect.signature(Referee.record_round).parameters)


def test_feed_updates_at_most_once_per_tape():
    ref = Referee(P)
    t = ref.feed(FEED).last_t + P.tape_s
    p1 = price_for_z(ref, 1.0)
    ref.record_round(FEED, t, P0, p1, C, "a", UP, 2, "b", DOWN, 2)
    once = ref.feed(FEED).snapshot()
    ref.record_round(FEED, t, P0, p1, C, "c", UP, 2, "d", DOWN, 2)
    ref.record_round(FEED, t + P.tape_s - 1, P0, p1, C, "e", UP, 2, "f", DOWN, 2)
    assert ref.feed(FEED).snapshot() == once
    ref.record_round(FEED, t + P.tape_s, P0, p1, C, "g", UP, 2, "h", DOWN, 2)
    assert ref.feed(FEED).snapshot() != once


def test_fighters_in_a_round_use_the_feed_state_from_before_the_round():
    a = Referee(P)
    b = Referee(P)
    t = a.feed(FEED).last_t + P.tape_s
    p1 = price_for_z(a, 1.0)
    a.record_round(FEED, t, P0, p1, C, "x", BURST, 2, "y", GUARD, 2)
    b.record_round(FEED, t, P0, p1, C, "y", GUARD, 2, "x", BURST, 2)
    assert a.fighter("x") == b.fighter("x")
    assert a.fighter("y") == b.fighter("y")


def test_bar_uses_family_size():
    ref = Referee(P)
    for k in (1, 2, 11):
        assert abs(ref.ln_bar(k) / WAD - math.log(k * (k + 1) * 100)) < 1e-9


def certify(ref, fighter, k):
    for i in range(5000):
        z = 2.0 if i % 2 else -2.0
        play(ref, fighter, UP if z > 0 else DOWN, z=z, k=k)
        if ref.fighter(fighter).k_at_cert:
            return
    raise AssertionError("never certified")


def test_ever_crossed_records_k_at_certification_and_stays_skilled():
    ref = Referee(P)
    certify(ref, "a", 2)
    v = ref.verdict_of("a", 2)
    assert v.skilled and v.k_at_cert == 2 and v.logW >= ref.ln_bar(2)
    # A later sibling raises the displayed bar but cannot undo certification or change its K.
    later = ref.verdict_of("a", 9)
    assert later.skilled and later.k_at_cert == 2 and later.lnBar == ref.ln_bar(9)


def test_sibling_raises_the_bar_before_certification():
    ref = Referee(P)
    for i in range(10_000):
        z = 2.0 if i % 2 else -2.0
        play(ref, "a", UP if z > 0 else DOWN, z=z, k=2)
        if ref.fighter("a").logW >= ref.ln_bar(2) - WAD // 10:
            break
    assert not ref.verdict_of("a", 2).skilled
    # One more name lifts the bar out of reach of the next round.
    k = 40
    play(ref, "a", UP, z=2.0, k=k)
    assert ref.fighter("a").k_at_cert == 0


def test_lapse_detector_flips_after_edge_turns_negative():
    ref = Referee(P)
    certify(ref, "a", 2)
    assert not ref.verdict_of("a", 2).lapsed
    for i in range(20_000):
        z = 2.0 if i % 2 else -2.0
        play(ref, "a", DOWN if z > 0 else UP, z=z, k=2)
        if ref.fighter("a").lapsed:
            break
    v = ref.verdict_of("a", 2)
    assert v.lapsed and v.skilled and v.k_at_cert == 2


def test_lapse_does_not_run_before_certification():
    ref = Referee(P)
    for i in range(50):
        play(ref, "a", DOWN, z=2.0)
    assert ref.fighter("a").logL == 0 and not ref.fighter("a").lapsed


def test_always_one_move_never_builds_evidence():
    rng = random.Random(11)
    for move in (UP, DOWN, GUARD, BURST):
        ref = Referee(P)
        peak = 0
        for _ in range(2000):
            play(ref, "a", move, z=rng.gauss(0, 1))
            peak = max(peak, ref.fighter("a").logW)
        assert peak < ref.ln_bar(1)


def test_drift_allowance_is_near_zero_for_stable_habits():
    rng = random.Random(5)
    ref = Referee(P)
    for _ in range(600):
        play(ref, "a", rng.randrange(4), z=rng.gauss(0, 1))
    s, f = ref.fighter("a"), ref.feed(FEED)
    assert ref.drift_penalty(s, f, C) / WAD < 1.0


def test_drift_allowance_grows_when_habits_switch():
    rng = random.Random(5)
    ref = Referee(P)
    for _ in range(300):
        play(ref, "a", GUARD, z=rng.gauss(0, 1))
    calm = ref.drift_d(ref.fighter("a"))
    for _ in range(8):
        play(ref, "a", BURST, z=rng.gauss(0, 1))
    assert ref.drift_d(ref.fighter("a")) > calm + WAD // 4
