#!/usr/bin/env bash
# One command: render the labeled clips, run busk's analyzer on each, score, write results JSON.
#   benchmark/run.sh                          # results -> benchmark/results/latest.json
#   benchmark/run.sh --baseline benchmark/baselines/main.json   # also compare; exit 1 on regression
set -euo pipefail
cd "$(dirname "$0")/.."
PY=${PYTHON:-python3}
"$PY" -c "import numpy, PIL, imageio_ffmpeg" 2>/dev/null || "$PY" -m pip install -q -r benchmark/requirements.txt
PYTHONPATH="benchmark${PYTHONPATH:+:$PYTHONPATH}" exec "$PY" -m busk_bench run "$@"
