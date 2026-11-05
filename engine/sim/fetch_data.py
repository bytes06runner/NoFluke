"""Downloads recorded 1 s prices for validation into engine/data/. Nothing here is committed."""
import datetime as dt
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np

from nofluke.params import load_params

DATA = Path(__file__).resolve().parents[1] / "data"


def fetch_day(base: str, symbol: str, day: dt.date) -> np.ndarray:
    name = f"{symbol}-1s-{day.isoformat()}"
    url = f"{base}/{symbol}/1s/{name}.zip"
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "nofluke-validation"}), timeout=120) as r:
        blob = r.read()
    with zipfile.ZipFile(io.BytesIO(blob)) as z, z.open(z.namelist()[0]) as f:
        rows = np.loadtxt(f, delimiter=",", usecols=(0, 4), dtype=np.float64)
    return rows


def main() -> None:
    raw = load_params().raw
    v = raw["validation"]
    end = dt.date.fromisoformat(v["dataEndDate"])
    days = [end - dt.timedelta(days=i) for i in range(v["dataDays"] - 1, -1, -1)]
    DATA.mkdir(exist_ok=True)
    for name in raw["feeds"]["order"]:
        e = raw["feeds"]["entries"][name]
        symbol = e["binanceSymbol"]
        out = DATA / f"{e['slug']}.npz"
        if out.exists():
            print(symbol, "already downloaded")
            continue
        parts = []
        for day in days:
            rows = fetch_day(v["dataBaseUrl"], symbol, day)
            parts.append(rows)
            print(symbol, day, len(rows), flush=True)
        all_rows = np.concatenate(parts)
        ts = all_rows[:, 0].astype(np.int64)
        # Binance moved some files from milliseconds to microseconds: normalise to whole seconds.
        ts = np.where(ts > 10**14, ts // 10**6, ts // 10**3)
        np.savez_compressed(out, t=ts, close=all_rows[:, 1])
        print(symbol, "saved", len(ts), flush=True)


if __name__ == "__main__":
    sys.exit(main())
