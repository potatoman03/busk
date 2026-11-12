#!/usr/bin/env bash
# Prints an xcodebuild destination for the newest available iPhone simulator.
set -euo pipefail
id=$(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
d = json.load(sys.stdin)["devices"]
best = None
for rt, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    if not m:
        continue
    v = (int(m.group(1)), int(m.group(2)))
    for dev in devs:
        if dev["name"].startswith("iPhone") and (best is None or v > best[0]):
            best = (v, dev["udid"])
print(best[1] if best else "")
')
[ -n "$id" ] || { echo "no iPhone simulator found" >&2; exit 1; }
echo "platform=iOS Simulator,id=$id"
