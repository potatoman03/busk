#!/usr/bin/env python3
"""Clean real clips through the live-camera path: raw video (no keypoint sidecar) through Apple Vision with the app's live
shooter tracking, at the camera's landscape and portrait framings and at frame rates a phone can fall to, compared with
the clip's Vision keypoint sidecar. Every run should count one shot and coach nothing.

Needs the clips and sidecars from scripts/real-flaw-eval.py (benchmark/.cache/real-flaws). Usage: scripts/raw-video-eval.py
"""
import json, statistics, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REAL = REPO / "benchmark/.cache/real-flaws"
OUT = REAL / "raw"
BIN = REPO / ".build/release/busk-analyze"
CLIPS = {"mcandrew_free_throw": "front", "kobe_bryant_warmup_free_throw": "front", "tolo_free_throw": "front", "research_jump_shot": "side"}


def analyze(video, view, out, keypoints=None):
    cmd = [str(BIN), "--video", str(video), "--handedness", "right", "--view", view, "--output", str(out)]
    cmd += ["--keypoints", str(keypoints)] if keypoints else ["--live-tracking", "1", "--save-keypoints", str(out.with_suffix(".keypoints.json"))]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        return None, f"exit {p.returncode}: {p.stderr.strip().splitlines()[-1] if p.stderr.strip() else ''}"
    return json.loads(out.read_text()).get("shots", []), None


def main():
    subprocess.run(["swift", "build", "-c", "release"], cwd=REPO, check=True, capture_output=True)
    OUT.mkdir(parents=True, exist_ok=True)
    rows, bad = [], 0
    for cid, view in CLIPS.items():
        video, kp = REAL / f"{cid}.mp4", REAL / f"{cid}.keypoints.json"
        if not video.exists() or not kp.exists():
            sys.exit(f"missing {video.name} or its sidecar: run scripts/real-flaw-eval.py first")
        # Portrait: a 9:16 crop around the shooter, as a phone held upright frames him.
        xs = [p[0] for f in json.loads(kp.read_text())["frames"] for p in f["joints"].values()]
        w = 405
        x = int(min(max(statistics.median(xs) * 1280 - w / 2, 0), 1280 - w))
        port = f"crop={w}:720:{x}:0,scale=720:1280"
        variants = {"sidecar": None, "raw 30fps": "fps=30", "portrait 30fps": port + ",fps=30", "raw 24fps": "fps=24",
                    "raw 15fps": "fps=15", "portrait 15fps": port + ",fps=15"}
        for name, vf in variants.items():
            tag = name.replace(" ", "_")
            if vf is None:
                shots, err = analyze(video, view, OUT / f"{cid}.{tag}.json", keypoints=kp)
            else:
                v = OUT / f"{cid}.{tag}.mp4"
                subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(video), "-vf", vf, "-an", str(v)], check=True)
                shots, err = analyze(v, view, OUT / f"{cid}.{tag}.json")
            flaws = sorted({f for s in shots or [] for f in s["flaws"]})
            ok = err is None and len(shots) == 1 and not flaws
            bad += not ok
            cue = err or (shots[0]["feedback"][0] if shots else "no shot")
            rows.append((cid, name, "-" if shots is None else len(shots), ",".join(flaws) or "-", cue, "ok" if ok else "FAIL"))
    print("| clip | input | shots | flaws | first cue | |\n|---|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(map(str, r)) + " |")
    print(f"\n{len(rows) - bad}/{len(rows)} clean runs coached as clean")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
