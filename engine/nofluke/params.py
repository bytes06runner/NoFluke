"""Loads config/params.json. No parameter is defined anywhere else."""
import json
from dataclasses import dataclass
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[2] / "config" / "params.json"


@dataclass(frozen=True)
class Params:
    alpha_inv: int
    z_clip: int
    delta: int
    payoff_per_z: int
    habit_horizon: int
    habit_short_horizon: int
    mean_horizon: int
    mean_short_horizon: int
    sigma_horizon: int
    kappa: int
    m: int
    lambda_max: int
    ons_beta: int
    lapse_lambda: int
    lapse_a: int
    lapse_edge_floor: int
    sigma_min_ppm: int
    tape_s: int
    feed_ids: tuple
    storm_c: dict
    sigma_init_ppm: dict
    raw: dict

    def replace(self, **kw):
        fields = {k: getattr(self, k) for k in self.__dataclass_fields__}
        fields.update(kw)
        return Params(**fields)


def load_params(path: Path = CONFIG) -> Params:
    d = json.loads(Path(path).read_text())
    r = d["referee"]
    entries = d["feeds"]["entries"]
    ids = tuple(entries[name]["id"] for name in d["feeds"]["order"])
    return Params(
        alpha_inv=r["alphaInv"],
        z_clip=int(r["zClipWad"]),
        delta=int(r["deltaPointsWad"]),
        payoff_per_z=d["match"]["payoffPerZ"],
        habit_horizon=r["habitHorizon"],
        habit_short_horizon=r["habitShortHorizon"],
        mean_horizon=r["meanHorizon"],
        mean_short_horizon=r["meanShortHorizon"],
        sigma_horizon=r["sigmaHorizon"],
        kappa=int(r["kappaWad"]),
        m=int(r["mPointsWad"]),
        lambda_max=int(r["lambdaMaxWad"]),
        ons_beta=int(r["onsBetaWad"]),
        lapse_lambda=int(r["lapseLambdaWad"]),
        lapse_a=r["lapseA"],
        lapse_edge_floor=int(r["lapseEdgeFloorWad"]),
        sigma_min_ppm=d["match"]["sigmaMinPpm"],
        tape_s=d["timing"]["tapeS"],
        feed_ids=ids,
        storm_c={entries[n]["id"]: int(entries[n]["stormCWad"]) for n in d["feeds"]["order"]},
        sigma_init_ppm={entries[n]["id"]: entries[n]["sigmaInitPpm"] for n in d["feeds"]["order"]},
        raw=d,
    )
