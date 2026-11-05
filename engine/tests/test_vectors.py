"""Replays shared/vectors/referee.json through the Python reference."""
import json

from nofluke.make_vectors import OUT, feed_json, fighter_json
from nofluke.params import load_params
from nofluke.referee import Referee, ln_wad

P = load_params()
V = json.loads(OUT.read_text())


def test_counts():
    assert len(V["histories"]) >= 12
    assert sum(len(h["steps"]) for h in V["histories"]) >= 80


def test_ln_wad_cases():
    for c in V["lnWad"]:
        assert ln_wad(int(c["x"])) == int(c["y"])


def test_bars():
    ref = Referee(P)
    for c in V["bars"]:
        assert ref.ln_bar(c["k"]) == int(c["lnBar"])


def test_histories():
    for h in V["histories"]:
        ref = Referee(P)
        for s in h["steps"]:
            if s["kind"] == "round":
                ref.record_round(s["feed"], s["t"], int(s["p0"]), int(s["p1"]), int(s["c"]), s["a"], s["moveA"], s["kA"], s["b"], s["moveB"], s["kB"])
                assert feed_json(ref.feed(s["feed"])) == s["feedAfter"], h["name"]
            else:
                ref.record_forfeit(s["a"], s["kA"])
            for name, want in s["fighters"].items():
                assert fighter_json(ref.fighter(name)) == want, h["name"]


def test_vectors_cover_the_named_cases():
    last = {h["name"]: h["steps"][-1] for h in V["histories"]}
    assert last["direction reader reaches the bar"]["fighters"]["A"]["kAtCert"] == 2
    assert last["certify then lapse"]["fighters"]["A"]["lapsed"] is True
    assert last["lambda clamps at zero"]["fighters"]["A"]["lambda"] == "0"
    assert int(last["lambda clamps at the maximum"]["fighters"]["A"]["lambda"]) == P.lambda_max
