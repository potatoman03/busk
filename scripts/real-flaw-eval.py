"""Inject known form flaws into the benchmark's real clips (Apple Vision keypoints) and check busk-analyze catches them.

Usage: python3 scripts/real-flaw-eval.py   (after benchmark/run.sh has downloaded the real clips and swift build -c release)
Each clean real clip is checked as-is (no flaw may be reported), then once per injected flaw: a 0.45 s hold at the set
point, the arm dropping right after the release, landing 0.3 body heights from the takeoff, and the body jumping
0.25 s earlier than the arm (so the release comes on the way down). Flaws are only injected where the taxonomy says
the view can show them, and drift / late release only on clips with a real jump.
"""
import copy, json, math, random, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REAL = REPO / "benchmark/.cache/real-flaws"
OUT = REAL / "out"
OUT.mkdir(parents=True, exist_ok=True)
CLIPS = []
for c in json.loads((REPO / "benchmark/real_clips.json").read_text())["clips"]:
    if c["flaws"]: continue
    CLIPS.append((c["source"]["sha1"], c["id"], c["view"], c["handedness"]))
    video, kp = REAL / f"{c['id']}.mp4", REAL / f"{c['id']}.keypoints.json"
    if not video.exists():
        video.write_bytes((REPO / f"benchmark/.cache/real/{c['source']['sha1']}.720p30.mp4").read_bytes())
    if not kp.exists():
        subprocess.run(["swift", str(REPO / "scripts/vision-keypoints.swift"), str(video), "--handedness", c["handedness"],
                        "--view", c["view"], "--output", str(kp)], check=True, capture_output=True)
TAX = {f["id"]: f for f in json.loads((REPO / "benchmark/taxonomy.json").read_text())["flaws"]}
random.seed(7)

def j(fr, n): return fr["joints"].get(n)

def angle(a, b, c):
    v1 = (a[0]-b[0], a[1]-b[1]); v2 = (c[0]-b[0], c[1]-b[1])
    d = math.hypot(*v1) * math.hypot(*v2)
    return math.degrees(math.acos(max(-1, min(1, (v1[0]*v2[0]+v1[1]*v2[1]) / d)))) if d else 180

def landmarks(frames, side):
    S, E, W = f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist"
    ok = [i for i, f in enumerate(frames) if all(j(f, n) for n in (S, E, W, "nose"))]
    # Wrist lift smoothed with a 5-frame median so a one-frame Vision glitch isn't taken for the release;
    # the release is the first frame within 0.02 body heights of the top, as the analyzer reads it.
    y = {i: j(frames[i], S)[1] - j(frames[i], W)[1] for i in ok}
    med = {}
    for i in ok:
        w = sorted(y[k] for k in range(i - 2, i + 3) if k in y)
        if len(w) >= 3: med[i] = w[len(w) // 2]
    hs0 = sorted(abs(j(f, "nose")[1] - (j(f, "left_ankle") or j(f, "right_ankle") or j(f, "nose"))[1]) for f in frames if j(f, "nose"))
    top = max(med.values())
    rel = min(i for i in med if med[i] >= top - 0.02 * hs0[len(hs0) // 2])
    win = [i for i in ok if i < rel and frames[rel]["t"] - frames[i]["t"] < 0.7 and j(frames[i], W)[1] < j(frames[i], S)[1]]
    st = min(win, key=lambda i: angle(j(frames[i], S), j(frames[i], E), j(frames[i], W))) if win else max(0, rel - 6)
    hs = [abs(j(f, "nose")[1] - (j(f, "left_ankle") or j(f, "right_ankle") or j(f, "nose"))[1]) for f in frames if j(f, "nose")]
    H = sorted(hs)[len(hs)//2] or 0.5
    return rel, st, H

def retime(frames, fps):
    for i, f in enumerate(frames): f["t"] = round(i / fps, 4)
    return frames

def jitter(f, s=0.0015):
    for n, p in f["joints"].items(): f["joints"][n] = [p[0] + random.gauss(0, s), p[1] + random.gauss(0, s)] + p[2:]
    return f

def inject(kp, flaw, side):
    kp = copy.deepcopy(kp); fr = kp["frames"]; fps = kp["fps"]
    rel, st, H = landmarks(fr, side)
    S, E, W = f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist"
    if flaw == "hitch_at_set_point":
        hold = [jitter(copy.deepcopy(fr[st])) for _ in range(int(0.45 * fps))]
        kp["frames"] = retime(fr[:st+1] + hold + fr[st+1:], fps)
    elif flaw == "no_follow_through":
        for k, i in enumerate(range(rel + 2, len(fr))):
            f = fr[i]; s = j(f, S); hip = j(f, f"{side}_hip")
            if not (s and hip and j(f, W) and j(f, E)): continue
            a = min(1, (k + 1) / 4)
            tw = [hip[0], hip[1] - 0.05 * H]; te = [(s[0]+hip[0])/2, (s[1]+hip[1])/2]
            for n, t in ((W, tw), (E, te)):
                p = j(f, n); f["joints"][n] = [p[0] + a*(t[0]-p[0]), p[1] + a*(t[1]-p[1])] + p[2:]
    elif flaw == "off_balance_drift":
        t0 = fr[st]["t"] - 0.25; t1 = fr[rel]["t"] + 0.5
        for f in fr:
            a = min(1, max(0, (f["t"] - t0) / (t1 - t0)))
            for n, p in f["joints"].items(): f["joints"][n] = [p[0] + a * 0.3 * H, p[1]] + p[2:]
    elif flaw == "releasing_on_the_way_down":
        # Jump earlier, keep the arm's timing: the body comes from 0.25 s later, the arms keep their own motion relative
        # to the shoulder, so the release then lands after the peak.
        d = int(0.25 * fps); orig = copy.deepcopy(fr); n = len(fr)
        arm = ("elbow", "wrist")
        for i in range(max(0, st - int(0.6 * fps)), n):
            src = orig[min(n - 1, i + d)]
            for nm, p in orig[i]["joints"].items():
                if any(k in nm for k in arm):
                    sh = nm.split("_")[0] + "_shoulder"; s0, s1 = j(orig[i], sh), j(src, sh)
                    q = [p[0] + s1[0] - s0[0], p[1] + s1[1] - s0[1]] + p[2:] if s0 and s1 else None
                else:
                    q = j(src, nm)
                if q: fr[i]["joints"][nm] = q
    return kp

def analyze(video, kp, view, hand, name):
    k = OUT / f"{name}.keypoints.json"; o = OUT / f"{name}.json"
    k.write_text(json.dumps(kp))
    subprocess.run([str(REPO / ".build/release/busk-analyze"), "--video", str(video), "--handedness", hand,
                    "--keypoints", str(k), "--output", str(o), "--view", view], check=True, capture_output=True)
    d = json.loads(o.read_text())
    return d["shots"]

FLAWS = ["hitch_at_set_point", "no_follow_through", "off_balance_drift", "releasing_on_the_way_down"]
rows = []
for sha, cid, view, hand in CLIPS:
    kp = json.loads((REAL / f"{cid}.keypoints.json").read_text()); side = hand
    for flaw in [None] + FLAWS:
        if flaw and view not in TAX[flaw]["views"]: continue
        if flaw in ("releasing_on_the_way_down", "off_balance_drift") and not jumps: continue  # no jump to drift on or come down from
        name = f"{cid}__{flaw or 'clean'}"
        if flaw is None: jumps = None
        shots = analyze(REAL / f"{cid}.mp4", inject(kp, flaw, side) if flaw else kp, view, hand, name)
        got = sorted({f for s in shots for f in s.get("flaws", [])})
        fb = shots[0]["feedback"][0] if shots and shots[0]["feedback"] else "-"
        if flaw is None: jumps = bool(shots) and "balance" in shots[0]["busk"]["areas"]
        hit = (flaw in got) if flaw else (not got)
        rows.append((name, len(shots), got, fb, hit))
        print(f"{'PASS' if hit else 'MISS'}  {name:55s} shots={len(shots)} flaws={got} cue={fb!r}")
print(f"\n{sum(r[4] for r in rows)}/{len(rows)} pass")
