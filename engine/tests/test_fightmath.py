"""Match rules. The named cases also become the cross-language vectors."""
import pytest

from nofluke.fightmath import (
    BadPrice, Command, Fighter, MatchRound, SigmaBounds, Truncated, abs_, base_payoff, is_void, load_rules, resolve_match, resolve_round, z_wad,
)
from nofluke.referee import WAD

R = load_rules()
C = 486 * 10**15


def cmd(move, read=0, od=False):
    return Command(move, read, od)


def round_(z, ca, cb, a=None, b=None, c=C, voided=False):
    a = a or Fighter(R.hp_start, R.meter_start)
    b = b or Fighter(R.hp_start, R.meter_start)
    return a, b, resolve_round(R, a, b, ca, cb, z, c, voided)


def test_payoffs():
    assert base_payoff(R, 0, WAD, C) == 10 * WAD
    assert base_payoff(R, 1, WAD, C) == -10 * WAD
    assert base_payoff(R, 2, WAD, C) == 10 * (C - WAD)
    assert base_payoff(R, 3, -WAD, C) == 10 * (WAD - C)


def test_z_at_storm_line_pays_guard_and_burst_nothing():
    assert base_payoff(R, 2, C, C) == 0
    assert base_payoff(R, 3, C, C) == 0


def test_z_truncates_toward_zero():
    assert z_wad(1000, 999, 500) == -(10**24 // (1000 * 500))


def test_sigma_and_price_bounds():
    with pytest.raises(BadPrice):
        z_wad(0, 1, 500)
    with pytest.raises(BadPrice):
        z_wad(1, -1, 500)
    with pytest.raises(SigmaBounds):
        resolve_match(R, R.sigma_min - 1, C, [])
    with pytest.raises(SigmaBounds):
        resolve_match(R, R.sigma_max + 1, C, [])


def test_tie_under_one_point():
    a, b, r = round_(0, cmd(2), cmd(2))
    assert r.damage == 0 and r.loser == 0 and a.meter == R.meter_start + R.meter_win and b.meter == R.meter_start + R.meter_win


def test_damage_at_exactly_one_point_and_at_cap():
    # Up against guard: the gap is set by z, so pick z that makes it exact.
    _, b, r = round_(WAD // 10, cmd(0), cmd(0))
    assert r.damage == 0
    _, b, r = round_(WAD // 20, cmd(0), cmd(1))
    assert r.damage == R.damage_base + 2 * 1 and r.loser == 2
    _, b, r = round_(WAD, cmd(0), cmd(1))
    assert r.damage == R.damage_base + 2 * 20 and b.hp == R.hp_start - 50
    _, b, r = round_(50 * WAD, cmd(0), cmd(1))
    assert r.damage == 50


def test_overdrive_needs_meter_and_doubles():
    a = Fighter(R.hp_start, R.overdrive_cost - 1)
    a2, _, r = round_(WAD, cmd(0, od=True), cmd(2), a=a)
    assert not r.a.od and r.a.pay == 10 * WAD
    a = Fighter(R.hp_start, R.overdrive_cost)
    a2, _, r = round_(WAD, cmd(0, od=True), cmd(2), a=a)
    assert r.a.od and r.a.pay == 20 * WAD


def test_overdrive_doubles_a_loss():
    a = Fighter(R.hp_start, R.overdrive_cost)
    _, _, r = round_(-WAD, cmd(0, od=True), cmd(2), a=a)
    assert r.a.pay == -20 * WAD


def test_counter_hit_only_on_positive_payoff():
    _, _, r = round_(WAD, cmd(0, read=1), cmd(2))
    assert r.a.counter and r.a.pay == 15 * WAD
    _, _, r = round_(-WAD, cmd(0, read=1), cmd(2))
    assert not r.a.counter and r.a.pay == -10 * WAD


def test_meter_cap_on_win_and_loss():
    a = Fighter(R.hp_start, R.meter_cap)
    b = Fighter(R.hp_start, R.meter_cap)
    a, b, _ = round_(WAD, cmd(0), cmd(1), a=a, b=b)
    assert a.meter == R.meter_cap and b.meter == R.meter_cap


def test_void_changes_nothing():
    a = Fighter(R.hp_start, R.meter_cap)
    a, b, r = round_(WAD, cmd(0, od=True), cmd(1), a=a, voided=True)
    assert a.meter == R.meter_cap and a.hp == R.hp_start and b.hp == R.hp_start and r.damage == 0 and r.loser == 0


def test_is_void():
    assert not is_void(100, 1, -8, 101, 1, -8, 100)
    assert is_void(0, 1, -8, 101, 1, -8, 100)
    assert is_void(100, 1, -8, 101, 1, -7, 100)
    assert not is_void(10000, 100, -8, 10000, 100, -8, 100)
    assert is_void(10000, 101, -8, 10000, 100, -8, 100)
    assert not is_void(10000, 10**6, -8, 10000, 100, -8, 0)


P0 = 10**10
SIG = 1000


def up(z_milli):
    return P0 + P0 * z_milli * SIG // 10**9


def mr(p1, a=0, b=1, **kw):
    return MatchRound(P0, p1, kw.get("voided", False), kw.get("a_missing", False), kw.get("b_missing", False), cmd(a, kw.get("ra", 0)), cmd(b, kw.get("rb", 0)))


def test_ko_ends_the_match_early():
    m = resolve_match(R, SIG, C, [mr(up(2000))] * 3)
    assert (m.winner, m.reason, m.rounds) == (1, 0, 2)
    assert m.b.hp == 0


def test_truncated_transcripts_are_rejected():
    with pytest.raises(Truncated):
        resolve_match(R, SIG, C, [mr(up(50))] * 2)
    with pytest.raises(Truncated):
        resolve_match(R, SIG, C, [])


def test_tie_after_five_goes_to_sudden_death():
    flat = [mr(P0, a=2, b=2)] * 5
    with pytest.raises(Truncated):
        resolve_match(R, SIG, C, flat)
    m = resolve_match(R, SIG, C, flat + [mr(up(50))])
    assert (m.winner, m.reason, m.rounds) == (1, 1, 6)
    m = resolve_match(R, SIG, C, flat + [mr(P0, a=2, b=2)])
    assert (m.winner, m.reason, m.rounds) == (0, 3, 6)


def test_forfeit_beats_hp_lead_and_both_forfeit_is_a_draw():
    m = resolve_match(R, SIG, C, [mr(up(50)), mr(up(50), a_missing=True)])
    assert (m.winner, m.reason) == (2, 2)
    m = resolve_match(R, SIG, C, [mr(up(50), a_missing=True, b_missing=True)])
    assert (m.winner, m.reason) == (0, 2)
    m = resolve_match(R, SIG, C, [mr(up(50), a=4)])
    assert (m.winner, m.reason) == (2, 2)
    m = resolve_match(R, SIG, C, [mr(up(50), rb=255)])
    assert (m.winner, m.reason) == (1, 2)


def test_missing_reveal_on_void_round_still_forfeits():
    m = resolve_match(R, SIG, C, [mr(up(50), voided=True, a_missing=True)])
    assert (m.winner, m.reason) == (2, 2)


def test_void_uses_its_slot_and_every_void_draws():
    m = resolve_match(R, SIG, C, [mr(0, voided=True)] * 6)
    assert (m.winner, m.reason, m.rounds) == (0, 3, 6)


def test_extra_rounds_after_ko_are_ignored():
    m = resolve_match(R, SIG, C, [mr(up(2000))] * 6)
    assert m.b.hp == 0 and m.rounds < 6


def test_abs():
    assert abs_(-3) == 3


def test_vectors_have_the_required_cases():
    import json

    from nofluke.make_fight_vectors import OUT

    v = json.loads(OUT.read_text())
    assert v["roundCount"] >= 70 and v["matchCount"] >= 35 and v["rejectCount"] >= 7 and v["voidCount"] >= 11
    assert len(v["rounds"]) == v["roundCount"] * v["roundWidth"]
