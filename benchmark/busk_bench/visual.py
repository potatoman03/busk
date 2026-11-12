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
        """Have busk analyse this clip in-app, then screenshot its feedback."""
        if self.status != "recording":
            return None
        dest = self.data_dir / "Documents" / "benchmark" / f"{name}.keypoints.json"
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(keypoints, dest)
        p = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", self.device, BUSK_BUNDLE_ID,
                            "-replay-keypoints", str(dest), "-replay-label", name], capture_output=True, text=True)
        if p.returncode != 0:
            self.log(f"busk replay of {name} failed to launch: {p.stderr.strip()[-200:]}")
            return None
        time.sleep(1.5 + replay_seconds(json.loads(dest.read_text())))
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
                "mode": "in-app replay (-replay-keypoints)", "replayed_clips": self.replayed,
                "recording": str(self.recording) if self.status == "captured" else None,
                "screenshots": self.screenshots}
