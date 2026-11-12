"""Render a ShotModel to an mp4 plus a ground-truth 2D keypoint sidecar."""
from __future__ import annotations

import json
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from .kinematics import BALL_R, FPS, HOOP_X, JOINTS, RIM_Z, ShotModel, ShotParams

W, H = 1280, 720

CAMERAS = {
    # phone on a tripod level with the shooter's chest, perpendicular to the shot line
    "side": dict(pos=(1.0, -5.4, 1.35), look=(1.0, 0.0, 1.45), hfov=58.0),
    # phone under the basket, facing the shooter
    "front": dict(pos=(5.8, 0.3, 1.35), look=(0.0, 0.0, 1.25), hfov=62.0),
}

SKIN = {"light": (234, 196, 160), "tan": (198, 145, 100), "brown": (141, 93, 60), "dark": (92, 60, 40)}


class Camera:
    def __init__(self, pos, look, hfov):
        self.pos = np.array(pos, float)
        f = np.array(look, float) - self.pos
        self.fwd = f / np.linalg.norm(f)
        self.right = np.cross(self.fwd, np.array([0, 0, 1.0]))
        self.right /= np.linalg.norm(self.right)
        self.up = np.cross(self.right, self.fwd)
        self.f = (W / 2) / math.tan(math.radians(hfov) / 2)

    def project(self, p):
        d = np.asarray(p, float) - self.pos
        z = float(np.dot(d, self.fwd))
        z = max(z, 0.05)
        x = W / 2 + self.f * float(np.dot(d, self.right)) / z
        y = H / 2 - self.f * float(np.dot(d, self.up)) / z
        return x, y, z

    def scale(self, metres, depth):
        return self.f * metres / depth


def _capsule(draw, a, b, w, color):
    w = max(int(round(w)), 2)
    draw.line([a[:2], b[:2]], fill=color, width=w)
    r = w / 2
    for p in (a, b):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)


def _background(draw, cam, view):
    draw.rectangle([0, 0, W, H], fill=(196, 202, 210))
    floor = [cam.project(p) for p in [(-12, -10, 0), (14, -10, 0), (14, 12, 0), (-12, 12, 0)]]
    if view == "front":
        floor = [cam.project(p) for p in [(-14, -8, 0), (4.6, -8, 0), (4.6, 8, 0), (-14, 8, 0)]]
    draw.polygon([q[:2] for q in floor], fill=(201, 160, 112))
    for x in (0.0,):
        a, b = cam.project((x, -2.4, 0.001)), cam.project((x, 2.4, 0.001))
        draw.line([a[:2], b[:2]], fill=(245, 245, 245), width=3)
    if view == "side":
        pole_a, pole_b = cam.project((HOOP_X + 1.3, 0, 0)), cam.project((HOOP_X + 1.3, 0, RIM_Z + 0.4))
        draw.line([pole_a[:2], pole_b[:2]], fill=(70, 70, 75), width=10)
        bb = [cam.project(p) for p in [(HOOP_X + 0.38, 0, RIM_Z - 0.15), (HOOP_X + 0.38, 0, RIM_Z + 0.9)]]
        draw.line([bb[0][:2], bb[1][:2]], fill=(250, 250, 250), width=8)
        r1, r2 = cam.project((HOOP_X - 0.23, 0, RIM_Z)), cam.project((HOOP_X + 0.23, 0, RIM_Z))
        draw.line([r1[:2], r2[:2]], fill=(230, 80, 30), width=5)
    else:
        rim = [cam.project((HOOP_X + 0.23 * math.cos(a), 0.23 * math.sin(a), RIM_Z)) for a in np.linspace(0, 2 * math.pi, 24)]
        draw.line([q[:2] for q in rim] + [rim[0][:2]], fill=(230, 80, 30), width=6)


def render_frame(model: ShotModel, cam: Camera, view: str, t: float, look: dict):
    img = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(img)
    _background(draw, cam, view)
    st = model.state(t)
    j3 = st["joints"]
    j = {k: cam.project(v) for k, v in j3.items()}
    skin, jersey, shorts, shoe = look["skin"], look["jersey"], look["shorts"], (30, 30, 34)
    Hm = model.p.height_m
    items = []

    def seg(a, b, width_m, color):
        depth = (j[a][2] + j[b][2]) / 2
        items.append((depth, "cap", (j[a], j[b], cam.scale(width_m, depth), color)))

    for side in ("left", "right"):
        seg(f"{side}_hip", f"{side}_knee", 0.085 * Hm, shorts if True else skin)
        seg(f"{side}_knee", f"{side}_ankle", 0.058 * Hm, skin)
        seg(f"{side}_ankle", f"{side}_toe", 0.055 * Hm, shoe)
        seg(f"{side}_shoulder", f"{side}_elbow", 0.05 * Hm, skin)
        seg(f"{side}_elbow", f"{side}_wrist", 0.042 * Hm, skin)
        seg(f"{side}_wrist", f"{side}_hand_tip", 0.042 * Hm, skin)
    torso_pts = ["left_shoulder", "right_shoulder", "right_hip", "left_hip"]
    tdepth = sum(j[k][2] for k in torso_pts) / 4
    items.append((tdepth, "poly", ([j[k][:2] for k in torso_pts], jersey, cam.scale(0.06 * Hm, tdepth))))
    seg("neck", "head", 0.05 * Hm, skin)
    hd = j["head"]
    items.append((hd[2] - 0.01, "circle", (hd, cam.scale(0.062 * Hm, hd[2]), skin)))
    b = cam.project(st["ball"])
    items.append((b[2] - 0.02, "ball", (b, cam.scale(BALL_R, b[2]))))

    for depth, kind, data in sorted(items, key=lambda it: -it[0]):
        if kind == "cap":
            _capsule(draw, data[0], data[1], data[2], data[3])
        elif kind == "poly":
            pts, color, w = data
            draw.polygon(pts, fill=color)
            for i in range(4):
                _capsule(draw, (*pts[i], 0), (*pts[(i + 1) % 4], 0), w, color)
        elif kind == "circle":
            (x, y, _), r, color = data
            draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
            draw.chord([x - r, y - r, x + r, y + r * 0.2], 180, 360, fill=(25, 20, 18))
        elif kind == "ball":
            (x, y, _), r = data
            draw.ellipse([x - r, y - r, x + r, y + r], fill=(222, 110, 35), outline=(60, 30, 10), width=2)
            draw.line([x - r, y, x + r, y], fill=(60, 30, 10), width=2)
            draw.line([x, y - r, x, y + r], fill=(60, 30, 10), width=2)
    return img, j, b


def render_clip(spec: dict, out_dir: Path) -> dict:
    """Render one clip. Returns paths of the video and keypoint sidecar."""
    out_dir.mkdir(parents=True, exist_ok=True)
    video = out_dir / f"{spec['id']}.mp4"
    kp_path = out_dir / f"{spec['id']}.keypoints.json"
    params = ShotParams.from_dict(spec["params"])
    model = ShotModel(params)
    view = spec["view"]
    cam = Camera(**CAMERAS[view])
    look = spec.get("look", {})
    look = {
        "skin": SKIN[look.get("skin", "tan")],
        "jersey": tuple(look.get("jersey", (40, 90, 200))),
        "shorts": tuple(look.get("shorts", (30, 40, 70))),
    }
    lefty = spec.get("handedness", "right") == "left"
    n = int(math.ceil(model.tl.end * FPS))
    from imageio_ffmpeg import get_ffmpeg_exe

    proc = subprocess.Popen(
        [get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "veryfast",
         "-crf", "20", "-pix_fmt", "yuv420p", "-threads", "1", "-movflags", "+faststart", str(video)],
        stdin=subprocess.PIPE,
    )
    frames = []
    for i in range(n):
        t = i / FPS
        img, j, b = render_frame(model, cam, view, t, look)
        if lefty:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        proc.stdin.write(img.tobytes())
        pts = {}
        for name in JOINTS:
            x, y, _ = j[name]
            if lefty:
                x = W - x
                name = name.replace("right_", "@").replace("left_", "right_").replace("@", "left_")
            pts[name] = [round(x / W, 5), round(y / H, 5)]
        bx = W - b[0] if lefty else b[0]
        frames.append({"t": round(t, 4), "joints": pts,
                       "ball": [round(bx / W, 5), round(b[1] / H, 5), round(cam.scale(BALL_R, b[2]) / W, 5)]})
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError(f"ffmpeg failed for {spec['id']}")
    kp = {
        "format": "busk-bench-keypoints/1",
        "coordinate_space": "normalized image coordinates, origin top-left, x right, y down",
        "fps": FPS, "width": W, "height": H, "view": view,
        "handedness": "left" if lefty else "right",
        "joints": JOINTS, "frames": frames,
    }
    kp_path.write_text(json.dumps(kp, separators=(",", ":")))
    return {"video": video, "keypoints": kp_path, "frames": n}
