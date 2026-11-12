"""Capture the iOS Simulator screen during a run (macOS only).

Jonathan's rule: a benchmark run counts only with screenshots and a screen
recording of the busk app running. `run --capture-simulator` records the booted
simulator for the whole run and takes a screenshot after every clip.
"""
from __future__ import annotations

import platform
import shutil
import signal
import subprocess
from pathlib import Path


class SimulatorCapture:
    def __init__(self, out_dir: Path, device: str = "booted", log=print):
        self.out_dir, self.device, self.log = out_dir, device, log
        self.proc = None
        self.recording = None
        self.screenshots = []
        self.status = "not_started"
        self.error = None

    def available(self) -> str | None:
        if platform.system() != "Darwin":
            return "simulator capture needs macOS"
        if not shutil.which("xcrun"):
            return "xcrun not found (install Xcode)"
        p = subprocess.run(["xcrun", "simctl", "list", "devices", "booted"], capture_output=True, text=True)
        if p.returncode != 0 or "Booted" not in p.stdout:
            return "no booted simulator (boot one and launch busk first)"
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
        self.log(f"recording simulator to {self.recording}")
        return True

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
            self.status = "captured" if ok else "failed"
            if not ok:
                self.error = (self.proc.stderr.read().decode() if self.proc.stderr else "")[-500:]
            self.proc = None
        return self.summary()

    def summary(self):
        return {"status": self.status, "error": self.error,
                "recording": str(self.recording) if self.status == "captured" else None,
                "screenshots": self.screenshots}
