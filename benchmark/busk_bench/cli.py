"""Command line: `python -m busk_bench run|compare|render`."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import SCHEMA_VERSION
from .analyzer import prebuild, resolve_command, run_clip
from .dataset import BENCH_DIR, load_clips, load_taxonomy
from .heldout import load_heldout_clips
from .real import fetch as fetch_real, load_real_clips
from .scoring import score_clip, summarize
from .visual import SimulatorCapture

REPO_ROOT = BENCH_DIR.parent
DEFAULT_OUT = BENCH_DIR / "results" / "latest.json"
DEFAULT_CACHE = BENCH_DIR / ".cache"


def log(msg):
    print(f"[busk-bench] {msg}", file=sys.stderr, flush=True)


def _renderer_hash():
    h = hashlib.sha256()
    for name in ("kinematics.py", "render.py"):
        h.update((Path(__file__).parent / name).read_bytes())
    return h.hexdigest()[:12]


def _git(*args):
    try:
        return subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def render_all(clips, cache: Path, jobs: int):
    from .render import render_clip

    rh = _renderer_hash()
    paths = {}

    def one(c):
        key = hashlib.sha256(json.dumps(c.spec(), sort_keys=True).encode() + rh.encode()).hexdigest()[:12]
        d = cache / "clips" / f"{c.id}-{key}"
        video, kp = d / f"{c.id}.mp4", d / f"{c.id}.keypoints.json"
        if not (video.exists() and kp.exists()):
            render_clip(c.spec(), d)
        return c.id, video, kp

    with ThreadPoolExecutor(max_workers=jobs) as ex:
        for cid, v, k in ex.map(one, clips):
            paths[cid] = (v, k)
    return paths


def cmd_render(a):
    tax = load_taxonomy()
    clips, _, _ = load_clips(tax)
    clips += load_heldout_clips(tax, a.heldout_seed)[0]
    clips = _filter(clips, a.clips)
    paths = render_all(clips, Path(a.cache), a.jobs)
    for cid, (v, k) in paths.items():
        print(f"{cid}\t{v}\t{k}")
    return 0


def _filter(clips, spec):
    if not spec:
        return clips
    want = [s.strip() for s in spec.split(",") if s.strip()]
    return [c for c in clips if any(w in (c.id, c.archetype, c.tier, c.set) for w in want)]


def cmd_run(a):
    started = time.time()
    tax = load_taxonomy()
    sets = ["synthetic", "heldout", "real"] if a.set == "all" else [a.set]
    clips, versions, shas = [], [], []
    for name in sets:
        got, v, sha = {"synthetic": lambda: load_clips(tax), "heldout": lambda: load_heldout_clips(tax, a.heldout_seed),
                       "real": lambda: load_real_clips(tax)}[name]()
        clips += got
        versions.append(v if name == "synthetic" else f"{name}{v}")
        shas.append(sha)
    ds_version = "+".join(versions)
    ds_sha = shas[0] if sets == ["synthetic"] else hashlib.sha256(":".join(shas).encode()).hexdigest()
    clips = _filter(clips, a.clips)
    cache = Path(a.cache)
    synthetic = [c for c in clips if c.set != "real"]
    log(f"rendering {len(synthetic)} synthetic and held-out clips (cached in {cache})")
    paths = render_all(synthetic, cache, a.jobs)
    unavailable = {}
    for c in [c for c in clips if c.set == "real"]:
        try:
            paths[c.id] = (fetch_real(c, cache, log), None)
        except Exception as e:  # noqa: BLE001 - a missing real clip is reported, not fatal
            unavailable[c.id] = str(e)[-300:]
            log(f"real clip {c.id} unavailable, skipped: {e}")
    clips = [c for c in clips if c.id not in unavailable]

    argv, source = resolve_command(a.analyzer, REPO_ROOT)
    analyzer_status = "ok"
    build_error = None
    if argv is None:
        analyzer_status = "missing"
        log("no analyzer found: set BUSK_ANALYZER_CMD, pass --analyzer, or add the "
            "`busk-analyze` executable to Package.swift. Every clip scores 0.")
    else:
        build_error = prebuild(argv, source, REPO_ROOT, log)
        if build_error:
            analyzer_status = "build_failed"
            log("analyzer build failed; every clip scores 0")

    out_dir = cache / "outputs"
    out_dir.mkdir(parents=True, exist_ok=True)
    capture = None
    if a.capture_simulator:
        capture = SimulatorCapture(Path(a.visual_dir), a.simulator, log)
        capture.start()
    results, statuses = {}, {}
    for c in clips:
        video, kp = paths[c.id]
        if analyzer_status != "ok":
            status, out, err, secs = analyzer_status if analyzer_status != "missing" else "analyzer_missing", None, "", 0.0
        else:
            status, out, err, secs = run_clip(argv, c, video, None if a.no_keypoints else kp,
                                              out_dir / f"{c.id}.json", a.timeout, REPO_ROOT)
        if capture is not None and kp is not None:
            shot = capture.replay(c.id, kp)
            if shot:
                results.setdefault("_shots", {})[c.id] = shot
        r = score_clip(c, out, tax)
        statuses[status] = statuses.get(status, 0) + 1
        results[c.id] = r
        r.update({"clip": c.id, "set": c.set, "archetype": c.archetype, "tier": c.tier, "view": c.view,
                  "handedness": c.handedness, "status": status, "seconds": round(secs, 3),
                  "labeled_flaws": [f["id"] for f in c.observable],
                  "expected_advice": [tax.flaws[f["id"]].canonical_fix for f in c.observable]})
        if c.source:
            r["source"] = {k: c.source[k] for k in ("page", "license", "credit")}
        if out is not None:
            r["pose_source"] = out.get("pose_source")
        if err and status != "ok":
            r["error"] = err[-600:]
        if argv is not None and analyzer_status == "ok":
            log(f"{c.id:40s} {status:16s} score {r['score']:6.1f}")

    shots = results.pop("_shots", {})
    for cid, path in shots.items():
        results[cid]["screenshot"] = path
    visual = capture.stop() if capture is not None else {"status": "not_requested"}
    if analyzer_status == "ok" and statuses.get("ok", 0) < len(clips):
        analyzer_status = "partial" if statuses.get("ok") else "failed"

    agg = summarize(clips, results, tax)
    sets = {}
    for c in clips:
        sets.setdefault(c.set, []).append(results[c.id]["score"])
    agg["set_scores"] = {k: round(sum(v) / len(v), 1) for k, v in sets.items()}
    if "synthetic" in sets and "heldout" in sets:
        # Core clips the analyzer was tuned on minus clips it has never seen: a widening gap means overfitting.
        agg["generalization_gap"] = round(agg["set_scores"]["synthetic"] - agg["set_scores"]["heldout"], 1)
    doc = {
        "schema_version": SCHEMA_VERSION,
        "benchmark": {
            "taxonomy_version": tax.version, "taxonomy_sha256": tax.sha256,
            "dataset_version": ds_version, "dataset_sha256": ds_sha,
            "renderer": _renderer_hash(), "clip_ids": [c.id for c in clips],
        },
        "run": {
            "started_at": dt.datetime.fromtimestamp(started, dt.timezone.utc).isoformat(timespec="seconds"),
            "duration_s": round(time.time() - started, 1),
            "git_sha": os.environ.get("GITHUB_SHA") or _git("rev-parse", "HEAD"),
            "git_ref": os.environ.get("GITHUB_REF_NAME") or _git("rev-parse", "--abbrev-ref", "HEAD"),
            "analyzer_command": argv, "analyzer_source": source, "analyzer_status": analyzer_status,
            "clip_statuses": statuses, "real_unavailable": unavailable, "keypoints_provided": not a.no_keypoints,
            "analyzer_build_error": build_error,
            "visual_evidence": visual,
        },
        **agg,
        "clips": [results[c.id] for c in clips],
    }
    out_path = Path(a.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(doc, indent=2) + "\n")
    print_summary(doc)
    print("  sets    " + "  ".join(f"{k} {v:5.1f}" for k, v in doc["set_scores"].items())
          + (f"   gap {doc['generalization_gap']:+.1f}" if "generalization_gap" in doc else "")
          + (f"   ({len(unavailable)} real clips unavailable)" if unavailable else ""))
    log(f"wrote {out_path}")
    rc = 0
    if a.baseline:
        rc = compare_files(Path(a.baseline), out_path, a)
    if a.require_analyzer and analyzer_status != "ok":
        rc = rc or 2
    if a.require_visuals and visual.get("status") != "captured":
        log(f"visual evidence missing: {visual.get('error') or visual.get('status')}")
        rc = rc or 3
    return rc


def print_summary(doc):
    s = doc["summary"]
    fmt = lambda v: "  n/a" if v is None else f"{v:5.1f}"
    pct = lambda v: "  n/a" if v is None else f"{100 * v:4.0f}%"
    print(f"busk shooting-feedback benchmark  analyzer={doc['run']['analyzer_status']}  clips={s['clips']}")
    print(f"  overall {fmt(s['overall_score'])}   flawed {fmt(s['flawed_clip_score'])}   clean {fmt(s['clean_clip_score'])}")
    print("  tiers   " + "  ".join(f"{t} {fmt(v['score'])}" for t, v in s["tiers"].items()))
    print(f"  detection {pct(s['detection'])}  advice {pct(s['advice'])}  priority {pct(s['priority'])}  "
          f"false alarms/clip {s['false_alarms_per_clip']}")
    print("  per flaw (detect / advice / false alarm):")
    for fid, v in doc["flaws"].items():
        rates = " ".join(pct(v[k]) for k in ("detection_rate", "advice_rate", "false_alarm_rate"))
        print(f"    {fid:28s} {rates}  (n={v['clips_with_flaw']})")


# ---- compare -------------------------------------------------------------

def compare_docs(old, new, max_overall_drop=2.0, max_tier_drop=5.0, max_flaw_drop=0.2, max_set_drop=2.0):
    comparable = old["benchmark"].get("taxonomy_sha256") == new["benchmark"].get("taxonomy_sha256") and \
        old["benchmark"].get("dataset_sha256") == new["benchmark"].get("dataset_sha256") and \
        old["benchmark"].get("clip_ids") == new["benchmark"].get("clip_ids")
    d = lambda a, b: None if a is None or b is None else round(b - a, 4)
    so, sn = old["summary"], new["summary"]
    report = {
        "comparable": comparable,
        "old": {"git_sha": old["run"].get("git_sha"), "overall": so["overall_score"]},
        "new": {"git_sha": new["run"].get("git_sha"), "overall": sn["overall_score"]},
        "delta": {
            "overall": d(so["overall_score"], sn["overall_score"]),
            "tiers": {t: d(so["tiers"].get(t, {}).get("score"), v["score"]) for t, v in sn["tiers"].items()},
            "sets": {k: d(old.get("set_scores", {}).get(k), v) for k, v in new.get("set_scores", {}).items()},
            "flaws_advice": {f: d(old["flaws"].get(f, {}).get("advice_rate"), v["advice_rate"]) for f, v in new["flaws"].items()},
            "false_alarms_per_clip": d(so["false_alarms_per_clip"], sn["false_alarms_per_clip"]),
        },
        "regressions": [],
        "clip_changes": [],
    }
    if not comparable:
        report["note"] = "taxonomy, dataset or clip set changed; deltas are informational only"
        return report
    oc = {c["clip"]: c for c in old["clips"]}
    for c in new["clips"]:
        o = oc.get(c["clip"])
        if o and abs(c["score"] - o["score"]) >= 0.05:
            report["clip_changes"].append({"clip": c["clip"], "old": o["score"], "new": c["score"],
                                           "new_false_alarms": sorted(set(c["false_alarms"]) - set(o["false_alarms"])),
                                           "lost_advice": sorted(set(o["advised"]) - set(c["advised"]))})
    report["clip_changes"].sort(key=lambda x: x["new"] - x["old"])
    r = report["regressions"]
    dl = report["delta"]
    if dl["overall"] is not None and dl["overall"] < -max_overall_drop:
        r.append(f"overall score dropped {-dl['overall']:.1f} (limit {max_overall_drop})")
    for t, v in dl["tiers"].items():
        if v is not None and v < -max_tier_drop:
            r.append(f"{t} tier dropped {-v:.1f} (limit {max_tier_drop})")
    for k, v in dl["sets"].items():
        if v is not None and v < -max_set_drop:
            r.append(f"{k} set dropped {-v:.1f} (limit {max_set_drop})")
    for f, v in dl["flaws_advice"].items():
        if v is not None and v < -max_flaw_drop:
            r.append(f"advice rate for {f} dropped {-100 * v:.0f} pts (limit {100 * max_flaw_drop:.0f})")
    if sn["clean_clips_with_false_alarms"] > so["clean_clips_with_false_alarms"]:
        r.append("clean-form clips with false alarms rose "
                 f"{so['clean_clips_with_false_alarms']} -> {sn['clean_clips_with_false_alarms']}")
    return report


def compare_files(old_p: Path, new_p: Path, a) -> int:
    old, new = json.loads(old_p.read_text()), json.loads(new_p.read_text())
    rep = compare_docs(old, new, a.max_overall_drop, a.max_tier_drop, a.max_flaw_drop, a.max_set_drop)
    if getattr(a, "report", None):
        Path(a.report).write_text(json.dumps(rep, indent=2) + "\n")
    print(json.dumps(rep, indent=2) if getattr(a, "json", False) else _compare_text(rep))
    return 1 if rep["regressions"] else 0


def _compare_text(rep):
    lines = [f"compare {rep['old']['git_sha']} -> {rep['new']['git_sha']}: overall "
             f"{rep['old']['overall']} -> {rep['new']['overall']} ({rep['delta']['overall']:+})"
             if rep["delta"]["overall"] is not None else "compare: overall n/a"]
    if not rep["comparable"]:
        lines.append("NOT COMPARABLE: " + rep["note"])
    for x in rep["regressions"]:
        lines.append("REGRESSION: " + x)
    for c in rep["clip_changes"][:10]:
        lines.append(f"  {c['clip']}: {c['old']:.1f} -> {c['new']:.1f}")
    if rep["comparable"] and not rep["regressions"]:
        lines.append("no regressions")
    return "\n".join(lines)


def cmd_compare(a):
    return compare_files(Path(a.old), Path(a.new), a)


def main(argv=None):
    p = argparse.ArgumentParser(prog="busk-bench", description="busk shooting-feedback benchmark")
    sub = p.add_subparsers(dest="cmd", required=True)

    def thresholds(sp):
        sp.add_argument("--max-overall-drop", type=float, default=2.0)
        sp.add_argument("--max-tier-drop", type=float, default=5.0)
        sp.add_argument("--max-set-drop", type=float, default=2.0, help="max drop in a set's score (synthetic/heldout/real)")
        sp.add_argument("--max-flaw-drop", type=float, default=0.2, help="max drop in a flaw's advice rate (0-1)")
        sp.add_argument("--report", help="also write the comparison JSON here")
        sp.add_argument("--json", action="store_true", help="print the comparison as JSON")

    r = sub.add_parser("run", help="render clips, run busk's analyzer on each, score, write results JSON")
    r.add_argument("--analyzer", help="analyzer command (default: $BUSK_ANALYZER_CMD, then the native "
                   "`busk-analyze` from Package.swift)")
    r.add_argument("--out", default=str(DEFAULT_OUT))
    r.add_argument("--set", choices=["all", "synthetic", "heldout", "real"], default="all",
                   help="core synthetic clips, held-out random shooters, fetched real footage, or all three (default)")
    r.add_argument("--heldout-seed", type=int, help="draw a fresh held-out set (default: the pinned seed in heldout.json)")
    r.add_argument("--clips", help="comma-separated clip ids, archetypes or tiers")
    r.add_argument("--cache", default=str(DEFAULT_CACHE))
    r.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    r.add_argument("--timeout", type=float, default=180.0, help="per-clip analyzer timeout (s)")
    r.add_argument("--no-keypoints", action="store_true", help="give the analyzer the video only")
    r.add_argument("--baseline", help="results JSON to compare against; exit 1 on regression")
    r.add_argument("--require-analyzer", action="store_true", help="exit 2 if the analyzer is missing or failing")
    r.add_argument("--capture-simulator", action="store_true",
                   help="macOS: record the iOS Simulator while busk analyses each clip in-app, screenshot its feedback")
    r.add_argument("--simulator", default="booted", help="simctl device (default: booted)")
    r.add_argument("--visual-dir", default=str(BENCH_DIR / "results" / "visual"))
    r.add_argument("--require-visuals", action="store_true", help="exit 3 unless the simulator recording was captured")
    thresholds(r)
    r.set_defaults(fn=cmd_run)

    c = sub.add_parser("compare", help="compare two results files; exit 1 on regression")
    c.add_argument("old")
    c.add_argument("new")
    thresholds(c)
    c.set_defaults(fn=cmd_compare)

    rd = sub.add_parser("render", help="render the clips only and print their paths")
    rd.add_argument("--clips")
    rd.add_argument("--heldout-seed", type=int)
    rd.add_argument("--cache", default=str(DEFAULT_CACHE))
    rd.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    rd.set_defaults(fn=cmd_render)

    a = p.parse_args(argv)
    return a.fn(a)
