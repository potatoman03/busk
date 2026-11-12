"""Invoke busk's form analysis through the benchmark contract (see benchmark/README.md)."""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import time
from pathlib import Path

SWIFT_PRODUCT = "busk-analyze"


def resolve_command(arg: str | None, repo_root: Path) -> tuple[list[str] | None, str]:
    """Return (argv, source). argv is None when busk has no analyzer yet."""
    if arg:
        return shlex.split(arg), "--analyzer"
    env = os.environ.get("BUSK_ANALYZER_CMD")
    if env:
        return shlex.split(env), "BUSK_ANALYZER_CMD"
    pkg = repo_root / "Package.swift"
    if pkg.exists() and SWIFT_PRODUCT in pkg.read_text():
        return ["swift", "run", "-c", "release", "--skip-build", SWIFT_PRODUCT], "Package.swift"
    return None, "not_found"


def prebuild(argv: list[str], source: str, repo_root: Path, log) -> str | None:
    if source != "Package.swift":
        return None
    log(f"building {SWIFT_PRODUCT} (swift build -c release)")
    p = subprocess.run(["swift", "build", "-c", "release", "--product", SWIFT_PRODUCT],
                       cwd=repo_root, capture_output=True, text=True)
    if p.returncode != 0:
        return (p.stderr or p.stdout)[-4000:]
    return None


def run_clip(argv, clip, video: Path, keypoints: Path | None, out_path: Path, timeout: float, cwd: Path):
    out_path.unlink(missing_ok=True)
    cmd = list(argv) + ["--video", str(video), "--handedness", clip.handedness, "--output", str(out_path)]
    if keypoints is not None:
        cmd += ["--keypoints", str(keypoints)]
    t0 = time.monotonic()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "timeout", None, "", time.monotonic() - t0
    except OSError as e:
        return "error", None, str(e), time.monotonic() - t0
    dt = time.monotonic() - t0
    tail = (p.stderr or "")[-1500:]
    if p.returncode != 0:
        return "error", None, tail, dt
    try:
        out = json.loads(out_path.read_text())
    except (OSError, ValueError) as e:
        return "invalid_output", None, f"{e}\n{tail}", dt
    if not isinstance(out, dict) or not isinstance(out.get("shots", []), list) or \
            not all(isinstance(s, dict) for s in out.get("shots", [])):
        return "invalid_output", None, "output must be an object with a `shots` list of objects", dt
    return "ok", out, tail, dt
