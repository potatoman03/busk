"""Score an analyzer's feedback for one clip against its labels.

Per clip (all values 0..1 unless noted):
  detection  severity-weighted share of observable labeled flaws the analyzer flagged
  advice     severity-weighted share of those flaws for which the feedback text contains a correct fix cue
  priority   1 if the analyzer's top item addresses the clip's primary (highest-severity) flaw
  false_alarms  count of flaws flagged or "fixed" that the shooter does not have
Clip score (0..100):
  flawed clip: 100 * (0.35 detection + 0.45 advice + 0.20 priority) - 10 per false alarm
  clean clip:  100 - 25 per false alarm
  no output / no shot detected: 0
"""
from __future__ import annotations

from .dataset import Clip, Taxonomy

W_DETECT, W_ADVICE, W_PRIORITY = 0.35, 0.45, 0.20
FLAWED_FA_PENALTY, CLEAN_FA_PENALTY = 10.0, 25.0


def _matches(patterns, line):
    return any(p.search(line) for p in patterns)


def normalize_output(out: dict) -> dict:
    """Collapse the analyzer's shots into one feedback list + flaw list."""
    shots = out.get("shots") or []
    feedback, flaws, reported_ids = [], [], False
    for s in shots:
        for line in s.get("feedback") or []:
            if isinstance(line, str) and line.strip():
                feedback.append(line.strip())
        if "flaws" in s:
            reported_ids = True
            for f in s.get("flaws") or []:
                if f not in flaws:
                    flaws.append(f)
    return {"shots": len(shots), "feedback": feedback, "flaws": flaws, "reported_ids": reported_ids}


def score_clip(clip: Clip, out: dict | None, tax: Taxonomy) -> dict:
    res = {"score": 0.0, "detection": 0.0, "advice": 0.0, "priority": 0.0,
           "detected": [], "advised": [], "missed": [], "false_alarms": [], "unknown_flaw_ids": []}
    if out is None:
        res["status_reason"] = "no_output"
        return res
    norm = normalize_output(out)
    res["feedback"] = norm["feedback"][:12]
    res["flaws_reported"] = norm["flaws"]
    if norm["shots"] == 0:
        res["status_reason"] = "no_shot_detected"
        return res

    corrective = [ln for ln in norm["feedback"] if not tax.praise.search(ln)]
    fixed = {fid for fid, f in tax.flaws.items() if any(_matches(f.fix, ln) for ln in corrective)}
    mentioned = {fid for fid, f in tax.flaws.items() if any(_matches(f.mention, ln) for ln in corrective)}
    res["unknown_flaw_ids"] = [f for f in norm["flaws"] if f not in tax.flaws]
    flagged = {f for f in norm["flaws"] if f in tax.flaws} if norm["reported_ids"] else (fixed | mentioned)

    labeled_all = {f["id"] for f in clip.flaws}
    obs = clip.observable
    # A flaw the shooter has but that this camera angle cannot show is neither credited nor penalized.
    fa = sorted((flagged | fixed) - labeled_all)
    res["false_alarms"] = fa

    if not obs:
        res["score"] = max(0.0, 100.0 - CLEAN_FA_PENALTY * len(fa))
        res["detection"] = res["advice"] = res["priority"] = None
        return res

    total = sum(f["severity"] for f in obs)
    det = sum(f["severity"] for f in obs if f["id"] in flagged)
    adv = sum(f["severity"] for f in obs if f["id"] in fixed)
    res["detected"] = [f["id"] for f in obs if f["id"] in flagged]
    res["advised"] = [f["id"] for f in obs if f["id"] in fixed]
    res["missed"] = [f["id"] for f in obs if f["id"] not in fixed]

    primary = tax.flaws[clip.primary]
    top_ok = False
    if norm["reported_ids"] and norm["flaws"]:
        top_ok = norm["flaws"][0] == clip.primary
    if not top_ok and corrective:
        top_ok = _matches(primary.fix, corrective[0]) or _matches(primary.mention, corrective[0])
    res["detection"] = det / total
    res["advice"] = adv / total
    res["priority"] = 1.0 if top_ok else 0.0
    raw = 100.0 * (W_DETECT * res["detection"] + W_ADVICE * res["advice"] + W_PRIORITY * res["priority"])
    res["score"] = max(0.0, raw - FLAWED_FA_PENALTY * len(fa))
    return res


def _mean(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs), 4) if xs else None


def summarize(clips: list[Clip], results: dict, tax: Taxonomy) -> dict:
    by_id = {c.id: c for c in clips}
    scored = [results[c.id] for c in clips]
    tiers, views = {}, {}
    for c in clips:
        tiers.setdefault(c.tier, []).append(results[c.id]["score"])
        views.setdefault(c.view, []).append(results[c.id]["score"])
    flaws = {}
    for fid in tax.flaws:
        present = [c for c in clips if fid in {f["id"] for f in c.observable}]
        absent = [c for c in clips if fid not in {f["id"] for f in c.flaws}]
        flaws[fid] = {
            "clips_with_flaw": len(present),
            "detection_rate": _mean([1.0 if fid in results[c.id]["detected"] else 0.0 for c in present]),
            "advice_rate": _mean([1.0 if fid in results[c.id]["advised"] else 0.0 for c in present]),
            "false_alarm_rate": _mean([1.0 if fid in results[c.id]["false_alarms"] else 0.0 for c in absent]),
        }
    clean = [c for c in clips if not c.observable]
    flawed = [c for c in clips if c.observable]
    tier_order = ["beginner", "intermediate", "advanced", "elite"]
    summary = {
        "overall_score": _mean([r["score"] for r in scored]),
        "clips": len(clips),
        "tiers": {t: {"score": _mean(tiers[t]), "clips": len(tiers[t])} for t in tier_order if t in tiers},
        "views": {v: {"score": _mean(s), "clips": len(s)} for v, s in sorted(views.items())},
        "flawed_clip_score": _mean([results[c.id]["score"] for c in flawed]),
        "clean_clip_score": _mean([results[c.id]["score"] for c in clean]),
        "detection": _mean([results[c.id]["detection"] for c in flawed]),
        "advice": _mean([results[c.id]["advice"] for c in flawed]),
        "priority": _mean([results[c.id]["priority"] for c in flawed]),
        "false_alarms_per_clip": _mean([len(results[c.id]["false_alarms"]) for c in clips]),
        "clean_clips_with_false_alarms": sum(1 for c in clean if results[c.id]["false_alarms"]),
    }
    weak = sorted(
        ({"flaw": fid, "advice_rate": v["advice_rate"], "detection_rate": v["detection_rate"],
          "false_alarm_rate": v["false_alarm_rate"]} for fid, v in flaws.items() if v["clips_with_flaw"]),
        key=lambda w: (w["advice_rate"], w["detection_rate"], -(w["false_alarm_rate"] or 0), w["flaw"]),
    )
    over_called = sorted(
        ({"flaw": fid, "false_alarm_rate": v["false_alarm_rate"]} for fid, v in flaws.items() if v["false_alarm_rate"]),
        key=lambda w: -w["false_alarm_rate"],
    )
    worst_clips = sorted(((results[c]["score"], c) for c in by_id))[:5]
    return {
        "summary": summary,
        "flaws": flaws,
        "weakest": {
            "flaws_by_advice": weak[:5],
            "over_called_flaws": over_called[:5],
            "lowest_tier": min(summary["tiers"].items(), key=lambda kv: kv[1]["score"])[0] if summary["tiers"] else None,
            "lowest_clips": [{"clip": c, "score": s} for s, c in worst_clips],
        },
    }
