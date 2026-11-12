"""Shared argument parsing for the reference analyzers (same CLI busk must implement)."""
import argparse
import json


def parse():
    p = argparse.ArgumentParser()
    p.add_argument("--video", required=True)
    p.add_argument("--handedness", default="right", choices=["right", "left"])
    p.add_argument("--keypoints")
    p.add_argument("--view", choices=["side", "front"])
    p.add_argument("--output", required=True)
    p.add_argument("--debug", action="store_true")
    return p.parse_args()


def write(path, shots, **extra):
    with open(path, "w") as f:
        json.dump({"shots": shots, **extra}, f, indent=2)
