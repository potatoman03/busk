#!/usr/bin/env python3
"""Weak baseline: gives every shooter the same three popular tips, regardless of the video."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _contract import parse, write  # noqa: E402

a = parse()
write(a.output, [{"feedback": [
    "Bend your knees and use your legs.",
    "Keep your elbow tucked in under the ball.",
    "Hold your follow-through until the ball hits the rim.",
]}], pose_source="none")
