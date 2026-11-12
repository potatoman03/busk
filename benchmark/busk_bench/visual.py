"""Capture the iOS Simulator screen during a run (macOS only).

Jonathan's rule: a benchmark run counts only with screenshots and a screen
recording of busk analysing the benchmark's clips. `run --capture-simulator`
records the simulator for the whole run and, for every clip with keypoints,
relaunches busk with `-replay-keypoints` so the app analyses that clip in a live
session, then screenshots its feedback.
"""
from __future__ import annotations

import json
import platform
import shutil
import signal
import subprocess
import time
from pathlib import Path


BUSK_BUNDLE_ID = "com.potatoman03.busk"


def pick_device(booted: list[dict], requested: str, running: dict[str, bool],
                installed: dict[str, bool] | None = None) -> tuple[str | None, str | None]:
    """Choose the simulator to capture: (udid, error). `running`/`installed` map udid -> busk is running/installed.

    `simctl io booted` picks an arbitrary device when several are booted, so resolve it to the one
    running busk, else the only one with busk installed.
    """
    if requested != "booted":
        match = [d for d in booted if requested in (d["udid"], d["name"])]
        return (match[0]["udid"], None) if match else (None, f"simulator {requested!r} is not booted")
    if not booted:
        return None, "no booted simulator (boot one and launch busk first)"
    with_busk = [d for d in booted if running.get(d["udid"])]
    if with_busk:
        return with_busk[0]["udid"], None
    if len(booted) == 1:
        return booted[0]["udid"], None
    with_app = [d for d in booted if (installed or {}).get(d["udid"])]
    if len(with_app) == 1:
        return with_app[0]["udid"], None
    return None, "several simulators are booted and none is running busk; launch busk or pass --simulator UDID"


def _booted_devices() -> list[dict]:
    p = subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"], capture_output=True, text=True)
    if p.returncode != 0:
        return []
    return [d for devs in json.loads(p.stdout).get("devices", {}).values() for d in devs if d.get("state") == "Booted"]


def replay_seconds(keypoints: dict) -> float:
    """How long busk takes to play a clip in-app: the frames plus the 1.5 s it holds the last pose."""
    return len(keypoints.get("frames", [])) / float(keypoints.get("fps") or 30) + 1.5


# The simulator plays clips about 3.5x slower than real time; leave room for a slower or busier machine.
SLOWDOWN_ALLOWANCE = 8.0
MIN_WAIT_S = 30.0
SETTLE_S = 1.5  # let the coaching card finish animating in before the screenshot


def coaching_timeout(clip_seconds: float) -> float:
    return max(MIN_WAIT_S, SLOWDOWN_ALLOWANCE * clip_seconds)


def coached(status: dict | None, label: str, loops: bool) -> str | None:
    """Outcome of busk's replay status for this clip so far: "coached", "no_shot", or None while still playing.

    A keypoint replay counts once every frame has played and busk has coached a shot; a `-videoPath` clip loops
    and never finishes, so it counts at its first coached shot.
    """
    if not status or status.get("label") != label:
        return None
    if status.get("shots", 0) > 0 and (loops or status.get("finished")):
        return "coached"
    if status.get("finished"):
        return "no_shot"
    return None


def wait_for_coaching(read, label: str, loops: bool, timeout: float, sleep=time.sleep, clock=time.monotonic):
    """Poll `read()` (the replay status, or None) until busk coaches the clip: (outcome, seconds, last status)."""
    t0 = clock()
    status = None
    while True:
        status = read() or status
        outcome = coached(status, label, loops)
        waited = clock() - t0
        if outcome:
            return outcome, waited, status
        if waited >= timeout:
            return "timeout", waited, status
        sleep(0.5)


def _read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def save_keypoints(argv: list[str], clip, video: Path, dest: Path, cwd: Path, timeout: float = 300) -> str | None:
    """Have busk-analyze write the real clip's pose sidecar (the simulator has no Vision body pose model).

    Rewritten every run so the replayed poses always come from the current video and analyzer."""
    dest.unlink(missing_ok=True)
    out = dest.with_name(dest.stem + ".analysis.json")
    cmd = list(argv) + ["--video", str(video), "--handedness", clip.handedness, "--view", clip.view,
                        "--output", str(out), "--save-keypoints", str(dest)]
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return str(e)
    if p.returncode != 0 or not dest.exists():
        return (p.stderr or "busk-analyze wrote no keypoints (does it support --save-keypoints?)")[-300:]
    return None


def app_data_dir(udid: str) -> Path | None:
    p = subprocess.run(["xcrun", "simctl", "get_app_container", udid, BUSK_BUNDLE_ID, "data"],
                       capture_output=True, text=True)
    return Path(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else None


def busk_running(udid: str) -> bool:
    p = subprocess.run(["xcrun", "simctl", "spawn", udid, "launchctl", "list"], capture_output=True, text=True)
    return p.returncode == 0 and f"UIKitApplication:{BUSK_BUNDLE_ID}[" in p.stdout


class SimulatorCapture:
    def __init__(self, out_dir: Path, device: str = "booted", log=print):
        self.out_dir, self.requested, self.log = out_dir, device, log
        self.device = None
        self.device_name = None
        self.app_running = False
        self.proc = None
        self.recording = None
        self.screenshots = []
        self.replayed = []
        self.outcomes = {}
        self.data_dir = None
        self.status = "not_started"
        self.error = None

    def available(self) -> str | None:
        if platform.system() != "Darwin":
            return "simulator capture needs macOS"
        if not shutil.which("xcrun"):
            return "xcrun not found (install Xcode)"
        booted = _booted_devices()
        running = {d["udid"]: busk_running(d["udid"]) for d in booted}
        installed = {d["udid"]: app_data_dir(d["udid"]) is not None for d in booted}
        udid, err = pick_device(booted, self.requested, running, installed)
        if err:
            return err
        self.device = udid
        self.device_name = next(d["name"] for d in booted if d["udid"] == udid)
        self.app_running = running[udid]
        self.data_dir = app_data_dir(udid)
        if self.data_dir is None:
            return f"busk ({BUSK_BUNDLE_ID}) is not installed on {self.device_name}"
        return None

    def start(self):
        why = self.available()
        if why:
            self.status, self.error = "unavailable", why
            self.log(f"simulator capture unavailable: {why}")
            return False
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.recording = self.out_dir / "simulator.mp4"
        self.recording.unlink(missing_ok=True)
        self.proc = subprocess.Popen(
            ["xcrun", "simctl", "io", self.device, "recordVideo", "--codec", "h264", "--force", str(self.recording)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.status = "recording"
        time.sleep(2)  # recordVideo needs a moment before its first frame
        self.log(f"recording {self.device_name} ({self.device}) to {self.recording}")
        return True

    def replay(self, name: str, keypoints: Path):
        """Have busk analyse this rendered clip in-app, wait for its coaching, then screenshot it."""
        if self.status != "recording":
            return None
        dest = self.data_dir / "Documents" / "benchmark" / f"{name}.keypoints.json"
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(keypoints, dest)
        return self._run(name, ["-replay-keypoints", str(dest)], replay_seconds(json.loads(dest.read_text())),
                         loops=False)

    def replay_video(self, name: str, video: Path, sidecar: Path, view: str, handedness: str):
        """Have busk run a real clip in-app via `-videoPath` (pose from its sidecar), wait for coaching, screenshot."""
        if self.status != "recording":
            return None
        d = self.data_dir / "Documents" / "real"
        d.mkdir(parents=True, exist_ok=True)
        dest = d / f"{name}.mp4"
        shutil.copyfile(video, dest)
        shutil.copyfile(sidecar, d / f"{name}.keypoints.json")
        return self._run(name, ["-videoPath", str(dest), "-cameraView", view, "-handedness", handedness],
                         replay_seconds(json.loads(sidecar.read_text())), loops=True)

    def _run(self, name: str, args: list[str], clip_seconds: float, loops: bool):
        status_path = self.data_dir / "Documents" / "benchmark" / f"{name}.status.json"
        status_path.parent.mkdir(parents=True, exist_ok=True)
        status_path.unlink(missing_ok=True)
        p = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", self.device, BUSK_BUNDLE_ID,
                            *args, "-replay-label", name, "-replay-status", str(status_path)],
                           capture_output=True, text=True)
        if p.returncode != 0:
            self.log(f"busk replay of {name} failed to launch: {p.stderr.strip()[-200:]}")
            self.outcomes[name] = {"outcome": "launch_failed", "seconds": 0.0}
            return None
        timeout = coaching_timeout(clip_seconds)
        outcome, waited, st = wait_for_coaching(lambda: _read_json(status_path), name, loops, timeout)
        self.outcomes[name] = {"outcome": outcome, "seconds": round(waited, 1), "timeout_s": round(timeout, 1),
                               "shots": (st or {}).get("shots", 0), "cues": (st or {}).get("cues", [])}
        if outcome == "coached":
            time.sleep(SETTLE_S)
        else:
            self.log(f"IN-APP MISS {name}: {outcome} after {waited:.0f} s (busk showed no coaching card)")
        self.replayed.append(name)
        return self.screenshot(name)

    def screenshot(self, name: str):
        if self.status != "recording":
            return None
        path = self.out_dir / f"{name}.png"
        p = subprocess.run(["xcrun", "simctl", "io", self.device, "screenshot", str(path)], capture_output=True, text=True)
        if p.returncode == 0:
            self.screenshots.append(str(path))
            return str(path)
        return None

    def stop(self):
        if self.proc is not None:
            self.proc.send_signal(signal.SIGINT)
            try:
                self.proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            ok = self.recording is not None and self.recording.exists() and self.recording.stat().st_size > 0
            if ok and not self.replayed:
                ok, self.error = False, "busk analysed no clips in the simulator (none had keypoints)"
            if ok and not busk_running(self.device):
                ok, self.error = False, "busk stopped running during the recording"
            self.status = "captured" if ok else "failed"
            if not ok and not self.error:
                self.error = (self.proc.stderr.read().decode() if self.proc.stderr else "")[-500:]
            self.proc = None
        return self.summary()

    def summary(self):
        return {"status": self.status, "error": self.error,
                "device": self.device, "device_name": self.device_name, "app": BUSK_BUNDLE_ID,
                "mode": "in-app replay (-replay-keypoints, -videoPath for real clips)", "replayed_clips": self.replayed,
                "in_app": self.outcomes,
                "in_app_misses": [k for k, v in self.outcomes.items() if v["outcome"] != "coached"],
                "recording": str(self.recording) if self.status == "captured" else None,
                "screenshots": self.screenshots}
