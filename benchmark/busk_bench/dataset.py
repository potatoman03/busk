"""Load the flaw taxonomy and the labeled clip set."""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent.parent
TAXONOMY_PATH = BENCH_DIR / "taxonomy.json"
CLIPS_PATH = BENCH_DIR / "clips.json"


@dataclass
class Flaw:
    id: str
    name: str
    views: list
    label_rule: dict
    canonical_fix: str
    fix: list
    mention: list


@dataclass
class Taxonomy:
    version: str
    flaws: dict
    praise: re.Pattern
    sha256: str

    def ids(self):
        return list(self.flaws)


@dataclass
class Clip:
    id: str
    archetype: str
    tier: str
    view: str
    handedness: str
    description: str
    params: dict
    look: dict
    flaws: list  # every labeled flaw [{id, severity}]
    observable: list  # labeled flaws visible from this view, highest severity first
    set: str = "synthetic"  # "synthetic" (rendered) or "real" (fetched footage)
    source: dict | None = None  # provenance and license of real footage

    @property
    def primary(self):
        return self.observable[0]["id"] if self.observable else None

    def spec(self):
        return {"id": self.id, "view": self.view, "handedness": self.handedness,
                "params": self.params, "look": self.look}


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_taxonomy(path: Path = TAXONOMY_PATH) -> Taxonomy:
    raw = json.loads(path.read_text())
    flaws = {}
    for f in raw["flaws"]:
        flaws[f["id"]] = Flaw(
            id=f["id"], name=f["name"], views=f["views"], label_rule=f["label_rule"],
            canonical_fix=f["canonical_fix"],
            fix=[re.compile(p, re.I) for p in f["fix_patterns"]],
            mention=[re.compile(p, re.I) for p in f["mention_patterns"]],
        )
    return Taxonomy(raw["version"], flaws, re.compile(raw["praise_pattern"], re.I), _sha(path))


def load_clips(tax: Taxonomy, path: Path = CLIPS_PATH) -> tuple[list[Clip], str, str]:
    raw = json.loads(path.read_text())
    order = {fid: i for i, fid in enumerate(tax.flaws)}
    clips = []
    for a in raw["archetypes"]:
        for f in a["flaws"]:
            if f["id"] not in tax.flaws:
                raise ValueError(f"{a['id']}: unknown flaw {f['id']}")
        for view in a["views"]:
            obs = [f for f in a["flaws"] if view in tax.flaws[f["id"]].views]
            obs.sort(key=lambda f: (-f["severity"], order[f["id"]]))
            clips.append(Clip(
                id=f"{a['id']}__{view}", archetype=a["id"], tier=a["tier"], view=view,
                handedness=a.get("handedness", "right"), description=a["description"],
                params=a["params"], look=a.get("look", {}), flaws=a["flaws"], observable=obs,
            ))
    return clips, raw["version"], _sha(path)
