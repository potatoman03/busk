#!/usr/bin/env bash
# busk-analyze for the benchmark: builds busk's real ShotAnalyzer + FormEvaluator from Busk/ into a CLI, then runs it.
#   BUSK_ANALYZER_CMD=benchmark/adapters/busk-analyze/run.sh benchmark/run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
bin="$here/.build/release/busk-analyze"
srcs=("$root/Busk/Models/Pose.swift" "$root/Busk/Analysis/ShotAnalyzer.swift" "$root/Busk/Analysis/FormEvaluator.swift")
exec 9>"$here/.build.lock"
flock 9
if [ ! -x "$bin" ] || [ -n "$(find "${srcs[@]}" "$here/Sources" "$here/Package.swift" -newer "$bin" 2>/dev/null)" ]; then
  mkdir -p "$here/Sources/busk-analyze/App"
  cp "${srcs[@]}" "$here/Sources/busk-analyze/App/"
  swift build -c release --package-path "$here" >&2
fi
flock -u 9
exec "$bin" "$@"
