#!/usr/bin/env python3
"""Reference analyzer: simple rules on the ground-truth 2D keypoints sidecar.

Not busk. It shows the clips' flaws are recoverable from what the camera sees,
and gives a realistic non-trivial score to calibrate against. It deliberately has
no set-point rule, so `low_set_point` is always missed.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _contract import parse, write  # noqa: E402

FIX = {
    "low_set_point": "Bring the ball up to a set point above your forehead before you shoot.",
    "no_leg_drive": "Bend your knees more and drive up through your legs.",
    "releasing_on_the_way_down": "Release at the top of your jump, not on the way down.",
    "hitch_at_set_point": "Make it one smooth motion; don't pause at your set point.",
    "off_balance_drift": "Jump straight up and land where you took off.",
    "guide_hand_interference": "Keep your guide hand on the side and let it come off; don't push with it.",
    "elbow_flare": "Tuck your elbow under the ball.",
    "flat_arc": "Put more arc on the shot.",
    "no_follow_through": "Snap your wrist and hold your follow-through.",
}
PRIORITY = list(FIX)


def analyze(kp, hand):
    W, H, fps = kp["width"], kp["height"], kp["fps"]
    fr = kp["frames"]
    s, g = ("right", "left") if hand == "right" else ("left", "right")
    P = lambda i, n: (fr[i]["joints"][n][0] * W, fr[i]["joints"][n][1] * H)
    ball = lambda i: (fr[i]["ball"][0] * W, fr[i]["ball"][1] * H)
    n = len(fr)
    ank0 = (P(0, "left_ankle")[1] + P(0, "right_ankle")[1]) / 2
    hpx = (ank0 - P(0, "head")[1]) / 0.915  # pixels per body height
    z = lambda y: (ank0 - y) / hpx + 0.039  # height above floor, in body heights
    dist = lambda a, b: math.hypot(a[0] - b[0], a[1] - b[1])
    off0 = dist(ball(0), P(0, f"{s}_wrist"))
    rel = next(i for i in range(1, n) if abs(dist(ball(i), P(i, f"{s}_wrist")) - off0) > 0.012 * hpx) - 1
    root = [z(P(i, "root")[1]) for i in range(n)]
    ank = [z((P(i, "left_ankle")[1] + P(i, "right_ankle")[1]) / 2) for i in range(n)]
    top = max(range(n), key=lambda i: ank[i])
    air = []
    if ank[top] > ank[0] + 0.012:
        a_, b_ = top, top
        while a_ > 0 and ank[a_ - 1] > ank[0] + 0.012: a_ -= 1
        while b_ < n - 1 and ank[b_ + 1] > ank[-1] + 0.012: b_ += 1
        air = list(range(a_, b_ + 1))
    m = {}
    # legs: deepest hip drop before release
    m["hip_drop"] = root[0] - min(root[:rel])
    # timing relative to jump apex
    if len(air) >= 3:
        apex = max(air, key=lambda i: ank[i])
        m["release_timing"] = (rel - apex) / (len(air) / 2)
    else:
        m["release_timing"] = 0.0
    # set point: wrist (relative to shoulder) comes to rest before the release extension
    wy = [P(i, f"{s}_wrist")[1] for i in range(n)]
    wrel = [wy[i] - P(i, f"{s}_shoulder")[1] for i in range(n)]
    sp = [abs(wrel[i + 1] - wrel[i - 1]) / 2 / hpx * fps for i in range(1, n - 1)] + [9, 9]
    sp = [9] + sp
    lo = max(1, rel - int(0.7 * fps))
    setf = max(range(max(lo, rel - 8), rel), key=lambda i: sp[i])
    while setf > lo and sp[setf - 1] <= sp[setf]:
        setf -= 1
    a_, b_ = setf, setf
    while a_ > lo and sp[a_ - 1] < 0.08: a_ -= 1
    while b_ < rel and sp[b_ + 1] < 0.08: b_ += 1
    m["hitch_s"] = (b_ - a_ + 1) / fps if sp[setf] < 0.08 else 0.0
    # follow-through: time the shooting wrist stays above the head after release
    m["follow_s"] = sum(1 for i in range(rel, min(n, rel + fps)) if wy[i] < P(i, "head")[1]) / fps
    # launch angle from the first ball frames after release
    b0, b1 = ball(rel + 1), ball(min(rel + 4, n - 1))
    m["launch_deg"] = math.degrees(math.atan2(b0[1] - b1[1], abs(b1[0] - b0[0]) + 1e-6))
    # front view: elbow outside the wrist at the set point; guide hand travel at release
    m["elbow_out"] = abs(P(setf, f"{s}_elbow")[0] - P(setf, f"{s}_wrist")[0]) / hpx
    k = min(rel + 4, n - 1)
    rd = (P(k, "root")[0] - P(rel, "root")[0], P(k, "root")[1] - P(rel, "root")[1])
    gw0, gw1 = P(rel, f"{g}_wrist"), P(k, f"{g}_wrist")
    m["guide_travel"] = math.hypot(gw1[0] - gw0[0] - rd[0], gw1[1] - gw0[1] - rd[1]) / hpx
    # drift: where the feet land vs. where they started
    a0 = [(P(0, f"{x}_ankle")) for x in ("left", "right")]
    a1 = [(P(n - 1, f"{x}_ankle")) for x in ("left", "right")]
    dx = abs((a1[0][0] + a1[1][0]) - (a0[0][0] + a0[1][0])) / 2 / hpx
    h1 = (a1[0][1] + a1[1][1]) / 2 - P(n - 1, "head")[1]
    scale = abs(1 - (ank0 - P(0, "head")[1]) / max(h1, 1)) * 3.1  # depth change for front view
    m["drift"] = max(dx, scale) if kp["view"] == "front" else dx

    flaws = []
    side, front = kp["view"] == "side", kp["view"] == "front"
    if m["hip_drop"] < 0.015: flaws.append("no_leg_drive")
    if m["release_timing"] > 0.3: flaws.append("releasing_on_the_way_down")
    if m["hitch_s"] > 0.15: flaws.append("hitch_at_set_point")
    if m["drift"] > 0.16: flaws.append("off_balance_drift")
    if m["guide_travel"] > 0.05: flaws.append("guide_hand_interference")
    if front and m["elbow_out"] > 0.07: flaws.append("elbow_flare")
    if side and m["launch_deg"] < 40: flaws.append("flat_arc")
    if m["follow_s"] < 0.25: flaws.append("no_follow_through")
    flaws.sort(key=PRIORITY.index)
    return flaws, m


def main():
    a = parse()
    if not a.keypoints:
        write(a.output, [], pose_source="none")
        return
    kp = json.load(open(a.keypoints))
    flaws, m = analyze(kp, a.handedness)
    if a.debug:
        print(json.dumps({k: round(v, 3) for k, v in m.items()}), file=sys.stderr)
    fb = [FIX[f] for f in flaws] or ["Nice shot, clean mechanics."]
    write(a.output, [{"flaws": flaws, "feedback": fb}], pose_source="keypoints")


if __name__ == "__main__":
    main()
