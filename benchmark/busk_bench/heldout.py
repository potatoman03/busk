"""Held-out tier: seeded random shooters busk has never been scored on (config in heldout.json).

Only the generator and its parameter ranges are checked in. Each run draws the shooters from a seed (the pinned
seed by default, so runs stay comparable; `--heldout-seed` draws a fresh set), labels them with the taxonomy's label
rules and renders them like the core clips.
"""
from __future__ import annotations

import hashlib
import json
import math
import random
from pathlib import Path

from .dataset import BENCH_DIR, Clip, Taxonomy, _sha, coaching_order
from .kinematics import ShotParams

HELDOUT_PATH = BENCH_DIR / "heldout.json"
SKINS = ["light", "tan", "brown", "dark"]
OPS = {"<": lambda a, b: a < b, ">": lambda a, b: a > b}


def _uniform(rng, lo_hi):
    lo, hi = lo_hi
    return round(rng.uniform(lo, hi), 3)


def draw_shooter(rng: random.Random, cfg: dict, tax: Taxonomy) -> tuple[dict, str]:
    """Return (params, handedness) for one shooter."""
    weights = cfg["flaw_count_weights"]
    k = int(rng.choices(list(weights), weights=list(weights.values()))[0])
    flawed = set(rng.sample(sorted(cfg["flaw_params"]), k))
    params = {}
    for fid, fp in cfg["flaw_params"].items():
        v = _uniform(rng, fp["flawed" if fid in flawed else "clean"])
        if fp["param"] == "drift_m":
            # Mostly fading back or sideways, never toward the hoop.
            ang = rng.uniform(math.radians(100), math.radians(260))
            params["drift_x_m"], params["drift_y_m"] = round(v * math.cos(ang), 3), round(v * math.sin(ang), 3)
            if "off_balance_drift" in flawed:
                params["lean_deg"] = _uniform(rng, cfg["body"]["lean_deg_drift"])
        else:
            params[fp["param"]] = v
    body = cfg["body"]
    params["height_m"] = _uniform(rng, body["height_m"])
    params["tempo"] = _uniform(rng, body["tempo"])
    # Late release and drift happen in the air, so those shooters always leave the floor.
    airborne = flawed & {"releasing_on_the_way_down", "off_balance_drift"}
    jump = body["jump_height_m_no_leg_drive"] if "no_leg_drive" in flawed and not airborne else body["jump_height_m"]
    params["jump_height_m"] = _uniform(rng, jump)
    hand = "left" if rng.random() < cfg["left_handed_share"] else "right"
    return params, hand


def label(params: dict, cfg: dict, tax: Taxonomy) -> list[dict]:
    """Flaws by the taxonomy's label rules, in coaching priority. The first is severity 3; the rest by margin."""
    p = ShotParams.from_dict(params)
    found = []
    for fid, f in tax.flaws.items():
        rule = f.label_rule
        v, thr = p.value(rule["param"]), rule["value"]
        if not OPS[rule["op"]](v, thr):
            continue
        lo, hi = cfg["flaw_params"][fid]["flawed"]
        far = max(abs(lo - thr), abs(hi - thr))
        found.append({"id": fid, "margin": round(min(1.0, abs(v - thr) / far), 3) if far else 0.6, "severity": 0})
    found.sort(key=coaching_order(tax, {f["id"]: f["margin"] for f in found}))
    for i, f in enumerate(found):
        f["severity"] = 3 if i == 0 else 2 if f["margin"] >= 0.6 else 1
    return found


def tier(flaws: list) -> str:
    return "beginner" if len(flaws) >= 3 else "intermediate" if flaws else "advanced"


def load_heldout_clips(tax: Taxonomy, seed: int | None = None, path: Path = HELDOUT_PATH):
    """Return (clips, version, sha256). The sha covers the config, the generator and the seed."""
    cfg = json.loads(path.read_text())
    seed = cfg["seed"] if seed is None else seed
    rng = random.Random(seed)
    clips = []
    for i in range(cfg["shooters"]):
        params, hand = draw_shooter(rng, cfg, tax)
        flaws = label(params, cfg, tax)
        look = {"skin": rng.choice(SKINS), "jersey": [rng.randrange(256) for _ in range(3)],
                "shorts": [rng.randrange(160) for _ in range(3)]}
        aid = f"heldout_{i:02d}"
        desc = "Held-out random shooter: " + (", ".join(f["id"] for f in flaws) or "clean form")
        for view in cfg["views"]:
            obs = [f for f in flaws if view in tax.flaws[f["id"]].views]
            obs.sort(key=coaching_order(tax, {f["id"]: f["margin"] for f in flaws}))
            clips.append(Clip(id=f"{aid}__{view}", archetype=aid, tier=tier(flaws), view=view, handedness=hand,
                              description=desc, params=params, look=look, flaws=flaws, observable=obs,
                              set="heldout"))
    h = hashlib.sha256(f"{_sha(path)}:{_sha(Path(__file__))}:{seed}".encode()).hexdigest()
    return clips, f"{cfg['version']}-s{seed}", h
