#!/usr/bin/env python3
"""Cheating upper bound: reads the labels for the clip and returns the canonical advice.

Used to prove the scorer gives 100 to perfect feedback. Never use as a baseline.
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _contract import parse, write  # noqa: E402

BENCH = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BENCH))
from busk_bench.dataset import coaching_order, load_taxonomy  # noqa: E402
from busk_bench.heldout import label  # noqa: E402

a = parse()
clip_id = Path(a.video).stem
arch, view = clip_id.split("__")
tax = {f["id"]: f for f in json.loads((BENCH / "taxonomy.json").read_text())["flaws"]}
arche = {x["id"]: x for x in json.loads((BENCH / "clips.json").read_text())["archetypes"]}[arch]
full = load_taxonomy()
margins = {f["id"]: f["margin"] for f in label(arche["params"], json.loads((BENCH / "heldout.json").read_text()), full)}
obs = sorted((f for f in arche["flaws"] if view in tax[f["id"]]["views"]), key=coaching_order(full, margins))
feedback = [tax[f["id"]]["canonical_fix"] for f in obs] or ["Great shot, that's textbook form."]
write(a.output, [{"flaws": [f["id"] for f in obs], "feedback": feedback}], pose_source="labels")
