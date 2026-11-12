"""Parametric 3D jump-shot model.

World frame (metres): x points from the shooter to the hoop, y to the shooter's
left, z up. The model is built for a right-handed shooter; left-handed clips are
mirrored at render time.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, fields

import numpy as np

G = 9.81
HOOP_X = 4.6
RIM_Z = 3.05
BALL_R = 0.12
FPS = 30

JOINTS = [
    "head", "nose", "neck", "root",
    "right_shoulder", "right_elbow", "right_wrist", "right_hand_tip",
    "left_shoulder", "left_elbow", "left_wrist", "left_hand_tip",
    "right_hip", "right_knee", "right_ankle", "right_toe",
    "left_hip", "left_knee", "left_ankle", "left_toe",
]


@dataclass
class ShotParams:
    height_m: float = 1.88
    tempo: float = 1.0
    knee_bend_deg: float = 50.0
    jump_height_m: float = 0.18
    set_height: float = 0.97
    elbow_flare_deg: float = 6.0
    release_angle_deg: float = 48.0
    follow_hold_s: float = 0.6
    guide_push: float = 0.0
    release_timing: float = 0.0
    hitch_s: float = 0.0
    drift_x_m: float = 0.0
    drift_y_m: float = 0.0
    lean_deg: float = 0.0

    @classmethod
    def from_dict(cls, d: dict) -> "ShotParams":
        names = {f.name for f in fields(cls)}
        unknown = set(d) - names
        if unknown:
            raise ValueError(f"unknown shot params: {sorted(unknown)}")
        return cls(**d)

    @property
    def drift_m(self) -> float:
        return math.hypot(self.drift_x_m, self.drift_y_m)

    def value(self, name: str) -> float:
        return self.drift_m if name == "drift_m" else float(getattr(self, name))


def _ease(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def _lerp(a, b, u):
    return np.asarray(a) + (np.asarray(b) - np.asarray(a)) * u


def _unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def _ik_elbow(shoulder, wrist, upper, fore, pole):
    """Place the elbow of a 2-link arm, bending toward `pole`."""
    d = wrist - shoulder
    dist = min(np.linalg.norm(d), (upper + fore) * 0.999)
    axis = _unit(d)
    a = (upper ** 2 - fore ** 2 + dist ** 2) / (2 * dist)
    h = math.sqrt(max(upper ** 2 - a ** 2, 0.0))
    p = pole - axis * np.dot(pole, axis)
    p = _unit(p) if np.linalg.norm(p) > 1e-6 else np.array([0.0, 0.0, -1.0])
    return shoulder + axis * a + p * h


def _rotate(v, axis, ang):
    axis = _unit(axis)
    return (v * math.cos(ang) + np.cross(axis, v) * math.sin(ang)
            + axis * np.dot(axis, v) * (1 - math.cos(ang)))


@dataclass
class Timeline:
    dip_start: float
    dip_end: float
    takeoff: float
    arm_rise_start: float
    set_reached: float
    release_start: float
    release: float
    land: float
    air: float
    end: float
    events: dict = field(default_factory=dict)


def timeline(p: ShotParams) -> Timeline:
    tempo = p.tempo
    dip_s, extend_s, rel_s = 0.28 / tempo, 0.24 / tempo, 0.13 / tempo
    air = 2 * math.sqrt(2 * max(p.jump_height_m, 0.0) / G)
    tr = 10.0
    takeoff = tr - (air / 2) * (1 + p.release_timing) if air > 0 else tr - 0.02
    dip_end = takeoff - extend_s
    dip_start = dip_end - dip_s
    release_start = tr - rel_s
    set_reached = release_start - p.hitch_s
    arm_rise_start = min(dip_end - 0.05, set_reached - 0.22 / tempo)
    start = min(dip_start, arm_rise_start) - 0.4
    shift = -start
    land = takeoff + air
    end = max(land, tr + p.follow_hold_s) + 0.9
    tl = Timeline(dip_start + shift, dip_end + shift, takeoff + shift, arm_rise_start + shift,
                  set_reached + shift, release_start + shift, tr + shift, land + shift, air, end + shift)
    tl.events = {k: getattr(tl, k) for k in ("dip_start", "takeoff", "set_reached", "release", "land")}
    return tl


class ShotModel:
    def __init__(self, p: ShotParams):
        self.p = p
        self.tl = timeline(p)
        H = p.height_m
        self.L = dict(
            upper=0.186 * H, fore=0.146 * H, hand=0.10 * H, thigh=0.245 * H, shin=0.246 * H,
            ankle_z=0.039 * H, hip_w=0.085 * H, sh_w=0.125 * H, torso=0.29 * H, neck=0.06 * H,
            head=0.075 * H,
        )
        self._release_state = None
        self._off_at_release = np.zeros(3)
        self._ball_v = None
        self._precompute_release()

    # ---- body pieces -------------------------------------------------
    def _body_offset(self, t):
        p, tl = self.p, self.tl
        z = 0.0
        if tl.air > 0 and tl.takeoff <= t <= tl.land:
            u = t - tl.takeoff
            v0 = G * tl.air / 2
            z = v0 * u - 0.5 * G * u * u
        if tl.air > 0:
            frac = _ease((t - tl.takeoff) / tl.air)
        else:
            frac = _ease((t - tl.release) / 0.3)
        return np.array([p.drift_x_m * frac, p.drift_y_m * frac, z]), frac

    def _knee_flex(self, t):
        p, tl = self.p, self.tl
        k = math.radians(p.knee_bend_deg)
        if t < tl.dip_start:
            return math.radians(8)
        if t < tl.dip_end:
            return _lerp(math.radians(8), k, _ease((t - tl.dip_start) / (tl.dip_end - tl.dip_start)))
        if t < tl.takeoff:
            return _lerp(k, math.radians(2), _ease((t - tl.dip_end) / max(tl.takeoff - tl.dip_end, 1e-3)))
        if t < tl.land:
            return math.radians(4)
        u = t - tl.land
        absorb = math.radians(min(25, p.knee_bend_deg * 0.5 + 5))
        if u < 0.12:
            return _lerp(math.radians(4), absorb, _ease(u / 0.12))
        return _lerp(absorb, math.radians(8), _ease((u - 0.12) / 0.3))

    def _legs(self, t, off):
        L = self.L
        kf = self._knee_flex(t)
        th = kf / 2
        pts = {}
        for side, sy, fx in (("right", -1, 0.06), ("left", 1, -0.04)):
            ankle = np.array([fx * self.p.height_m / 1.88, sy * L["hip_w"] * 1.15, L["ankle_z"]]) + off
            knee = ankle + np.array([L["shin"] * math.sin(th), 0, L["shin"] * math.cos(th)])
            hip = knee + np.array([-L["thigh"] * math.sin(th), sy * 0.0, L["thigh"] * math.cos(th)])
            hip[1] = sy * L["hip_w"] + off[1]
            toe = ankle + np.array([0.14 * self.p.height_m / 1.88, sy * 0.02, -L["ankle_z"] * 0.8])
            pts.update({f"{side}_ankle": ankle, f"{side}_knee": knee, f"{side}_hip": hip, f"{side}_toe": toe})
        return pts, kf

    def _torso(self, t, legs, kf, drift_frac):
        L, p = self.L, self.p
        root = (legs["right_hip"] + legs["left_hip"]) / 2
        lean_fwd = kf * 0.35
        lean_back = math.radians(p.lean_deg) * drift_frac
        lean_dir = np.array([-1.0, 0, 0])
        if p.drift_m > 1e-6:
            lean_dir = _unit(np.array([p.drift_x_m, p.drift_y_m, 0.0]))
        up = np.array([0, 0, 1.0])
        up = _rotate(up, np.array([0, 1.0, 0]), lean_fwd)
        up = _rotate(up, np.cross(np.array([0, 0, 1.0]), lean_dir), lean_back)
        neck = root + up * L["torso"]
        head = neck + up * (L["neck"] + L["head"])
        nose = head + np.array([L["head"] * 0.9, 0, -L["head"] * 0.15])
        rs = neck + np.array([0.0, -L["sh_w"], -0.03])
        ls = neck + np.array([0.0, L["sh_w"], -0.03])
        return dict(root=root, neck=neck, head=head, nose=nose, right_shoulder=rs, left_shoulder=ls), up

    # ---- shooting arm -----------------------------------------------
    def _arm_targets(self, base):
        """Hand targets relative to the body root (no jump offset)."""
        H = self.p.height_m
        hold = np.array([0.24 * H / 1.88, -0.02, 0.0])
        pocket = np.array([0.20 * H / 1.88, -0.04, 0.0])
        set_pt = np.array([0.10 * H / 1.88, -0.07, 0.0])
        return hold, pocket, set_pt

    def _precompute_release(self):
        p, tl = self.p, self.tl
        st = self.state(tl.release, _ball=False)
        ball = st["ball"]
        th = math.radians(p.release_angle_deg)
        dx = max(HOOP_X - ball[0], 1.0)
        dz = RIM_Z - ball[2]
        denom = 2 * math.cos(th) ** 2 * (dx * math.tan(th) - dz)
        v = math.sqrt(G * dx * dx / denom) if denom > 0 else 9.0
        lat = math.radians(4.0) * p.guide_push + math.radians(p.elbow_flare_deg - 6) * 0.08
        self._ball_v = np.array([v * math.cos(th) * math.cos(lat), v * math.cos(th) * math.sin(lat), v * math.sin(th)])
        self._release_state = ball
        self._off_at_release = self._body_offset(tl.release)[0]

    def state(self, t, _ball=True):
        p, tl, L, H = self.p, self.tl, self.L, self.p.height_m
        off, drift_frac = self._body_offset(t)
        legs, kf = self._legs(t, off)
        torso, up = self._torso(t, legs, kf, drift_frac)
        pts = {**legs, **torso}
        rs, ls = torso["right_shoulder"], torso["left_shoulder"]
        root_z = torso["root"][2]

        hold, pocket, set_pt = self._arm_targets(None)
        hold_w = np.array([torso["root"][0] + hold[0], rs[1] + 0.12, root_z + 0.12 * H / 1.88])
        pocket_w = np.array([torso["root"][0] + pocket[0], rs[1] + 0.1, root_z + 0.05 * H / 1.88])
        set_z = p.set_height * H + off[2] + (torso["root"][2] - off[2] - self._stand_root_z())
        set_w = np.array([rs[0] + set_pt[0] + 0.03, rs[1] + 0.06, set_z - 0.10])
        th_arm = math.radians(min(p.release_angle_deg + 20, 82))
        reach = (L["upper"] + L["fore"]) * 0.96
        rel_w = rs + np.array([reach * math.cos(th_arm), 0.04, reach * math.sin(th_arm)])
        drop_w = np.array([rs[0] + 0.05, rs[1] - 0.05, root_z + 0.02])

        hand_flex = 0.0
        released = t >= tl.release
        hold_end = tl.release + p.follow_hold_s
        if t < tl.dip_start:
            w = hold_w
        elif t < tl.arm_rise_start:
            w = _lerp(hold_w, pocket_w, _ease((t - tl.dip_start) / max(tl.arm_rise_start - tl.dip_start, 1e-3)))
        elif t < tl.set_reached:
            u = _ease((t - tl.arm_rise_start) / max(tl.set_reached - tl.arm_rise_start, 1e-3))
            start = hold_w if tl.arm_rise_start <= tl.dip_start else pocket_w
            w = _lerp(start, set_w, u)
        elif t < tl.release_start:
            w = set_w
        elif t < tl.release:
            w = _lerp(set_w, rel_w, _ease((t - tl.release_start) / (tl.release - tl.release_start)))
        elif t < hold_end:
            w = rel_w
            hand_flex = math.radians(80 if p.follow_hold_s >= 0.15 else 20) * _ease((t - tl.release) / 0.08)
        else:
            u = _ease((t - hold_end) / (0.2 if p.follow_hold_s < 0.15 else 0.4))
            w = _lerp(rel_w, drop_w, u)
            hand_flex = math.radians(80 if p.follow_hold_s >= 0.15 else 20) * (1 - u)

        pole = np.array([0.15, 0.0, -1.0])
        flare = math.radians(p.elbow_flare_deg)
        pole = _rotate(pole, np.array([1.0, 0, 0]), flare)  # rotates the elbow out toward -y
        rw = w
        re = _ik_elbow(rs, rw, L["upper"], L["fore"], pole)
        fore_dir = _unit(rw - re)
        side_axis = np.cross(fore_dir, np.array([0, 1.0, 0]))
        hand_dir = _rotate(fore_dir, np.array([0, 1.0, 0]), hand_flex)
        if np.linalg.norm(side_axis) < 1e-6:
            hand_dir = fore_dir
        r_tip = rw + _unit(hand_dir) * L["hand"]

        # ball sits on the shooting hand until release
        if not released or not _ball or self._release_state is None:
            ball = rw + np.array([0.04, 0.05, 0.11])
        else:
            u = t - tl.release
            ball = self._release_state + self._ball_v * u + np.array([0, 0, -0.5 * G * u * u])

        # guide hand: on the side of the ball, then off (or pushing) at release
        g_side = np.array([0.0, 0.13, -0.02])
        pre_release = t < tl.release or self._release_state is None
        if pre_release:
            lw = ball + g_side
            if p.guide_push > 0.5 and t > tl.release - 0.06:
                lw = lw + np.array([0.08, -0.05, 0.03]) * _ease((t - (tl.release - 0.06)) / 0.06)
        else:
            u_rel = t - tl.release
            lw = self._release_state + g_side + (off - self._off_at_release)
            if p.guide_push > 0.5:
                lw = lw + np.array([0.08, -0.05, 0.03]) + np.array([0.20, -0.10, 0.06]) * _ease(u_rel / 0.12)
            if u_rel > 0.25:
                rest = np.array([ls[0] + 0.05, ls[1] + 0.06, root_z + 0.02])
                lw = _lerp(lw, rest, _ease((u_rel - 0.25) / 0.4))
        l_pole = np.array([0.1, 0.5, -1.0])
        le = _ik_elbow(ls, lw, L["upper"], L["fore"], l_pole)
        l_tip = lw + _unit(lw - le) * L["hand"] * 0.9
        pts.update(right_elbow=re, right_wrist=rw, right_hand_tip=r_tip,
                   left_elbow=le, left_wrist=lw, left_hand_tip=l_tip)
        return {"joints": pts, "ball": ball}

    def _stand_root_z(self):
        L = self.L
        th = math.radians(8) / 2
        return L["ankle_z"] + (L["shin"] + L["thigh"]) * math.cos(th)
