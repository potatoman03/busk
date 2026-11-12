# busk shooting-feedback benchmark

Scores busk's shooting form feedback against labeled shots, from complete beginners to elite shooters.
Each clip is labeled with the flaws it really has and the advice it should get. The benchmark plays every
clip through busk's form analysis and checks two things: does busk spot the real flaws, and does it give
the right fix? Clean (elite) form should get praise, not invented corrections.

## Run it

```bash
benchmark/run.sh                                        # writes benchmark/results/latest.json
benchmark/run.sh --baseline benchmark/baselines/main.json   # also compares; exits 1 on regression
python3 -m busk_bench compare OLD.json NEW.json         # (from benchmark/) compare two runs
```

It needs Python 3.10+ (`requirements.txt`: numpy, pillow, imageio-ffmpeg with its bundled ffmpeg). It runs
headless: clips are rendered deterministically on first use and cached in `benchmark/.cache/`.

| flag | meaning |
|---|---|
| `--analyzer CMD` | analyzer command (default `$BUSK_ANALYZER_CMD`, then busk's native `busk-analyze` from `Package.swift`, built with `swift build -c release`). Relative paths resolve from the repo root |
| `--set all\|synthetic\|heldout\|real` | which clips to score (default `all`) |
| `--heldout-seed N` | draw a fresh held-out set instead of the pinned one (not comparable with the baseline) |
| `--clips IDS` | comma-separated clip ids, archetypes, tiers or sets (e.g. `elite,rec_fader`) |
| `--no-keypoints` | give the analyzer only the video, so it must run its own pose detection |
| `--baseline FILE` | compare against a previous results file; exit 1 on regression |
| `--require-analyzer` | exit 2 if the analyzer is missing or fails on any clip |
| `--capture-simulator` | macOS: record the booted iOS Simulator for the whole run and take a screenshot after each clip (`--visual-dir`, `--simulator`) |
| `--require-visuals` | exit 3 unless the simulator recording was captured |

## Analyzer contract (for the busk app team)

busk exposes its form analysis as one command line tool. The default is a SwiftPM executable product
named `busk-analyze`; any other command works through `BUSK_ANALYZER_CMD`. For each clip the benchmark runs:

```
busk-analyze --video CLIP.mp4 --handedness right|left --view side|front --output OUT.json [--keypoints CLIP.keypoints.json]
```

* `--view`: the labelled camera view of the clip, as a user picks it in the app.

* `--video`: an H.264 MP4, 1280x720 at 30 fps, holding one jump shot filmed from the side or the front.
* `--keypoints` (passed unless `--no-keypoints`): ground-truth 2D pose for every frame
  (`busk-bench-keypoints/1`: normalized image coordinates; joints `head, nose, neck, root, {left,right}_{shoulder,elbow,wrist,hand_tip,hip,knee,ankle,toe}`;
  plus the ball centre and radius). Use it in place of Vision pose detection so the benchmark tests the
  coaching logic rather than the pose model. Ignoring it is allowed.
* Exit 0 and write this JSON to `--output` (anything else scores the clip 0):

```json
{
  "shots": [
    {
      "feedback": ["Tuck your shooting elbow under the ball.", "Hold your follow-through."],
      "flaws": ["elbow_flare", "no_follow_through"]
    }
  ],
  "pose_source": "vision"
}
```

* `feedback` (required): the cues busk would speak, most important first. These are the strings that get scored.
* `flaws` (optional): flaw ids from [`taxonomy.json`](taxonomy.json). When present they decide detection;
  without them, detection is inferred from the feedback text.
* Empty `shots` means "no shot detected" and scores 0. Clips get 180 s each (`--timeout`).

## What it scores

**Clips** ([`clips.json`](clips.json)): 14 shooter archetypes rendered from two cameras (side and front), 28
clips in total. There are 3 beginner archetypes with 4 to 6 flaws each, 5 intermediate archetypes with 1 or 2
flaws, 2 advanced archetypes, and 4 clean elite archetypes. The elite ones are modelled on Steph Curry's
quick one-motion release, Klay Thompson's textbook form, Kevin Durant's high release and a left-hander.
The shots are rendered from a parametric 3D body model (`busk_bench/kinematics.py`, `render.py`), so every
label is exact and the clips are identical on every run. They are mechanics models, not footage of those players.

**Flaws** ([`taxonomy.json`](taxonomy.json)): each flaw has a label rule on the model parameters (a test
checks every label against its rule), the camera views it can be seen from, and a canonical fix. It also
has the regexes that recognise someone naming the flaw and someone giving its fix. A flaw only counts for a
view where it is visible: elbow flare and guide-hand push are front-view only, a flat arc is side-view only.

| flaw | views | labeled when | right advice |
|---|---|---|---|
| `no_leg_drive` | side/front | knee bend < 25° | Bend your knees and drive up through your legs |
| `low_set_point` | side/front | set point < 0.86 x height | Set the ball above your forehead, don't push from the chest |
| `elbow_flare` | front | elbow flare > 20° | Tuck your shooting elbow under the ball |
| `flat_arc` | side | release angle < 40° | Put more arc on it (45-50°) |
| `no_follow_through` | side/front | follow-through held < 0.15 s | Snap your wrist and hold your follow-through |
| `guide_hand_interference` | front | guide hand pushes | Guide hand on the side, let it come off |
| `releasing_on_the_way_down` | side/front | release after 30% of the descent | Release at the top of your jump |
| `hitch_at_set_point` | side/front | pause at set > 0.25 s | One smooth motion, don't stop at the set point |
| `off_balance_drift` | side/front | drift > 0.3 m | Jump straight up, land where you took off |

**Score per clip** (0-100), defined in `busk_bench/scoring.py`:

* flawed clip: `100 x (0.35 detection + 0.45 advice + 0.20 priority) - 10 per false alarm`. Detection and
  advice are severity-weighted shares of the visible labeled flaws. Priority is 1 when the first cue
  addresses the most severe flaw.
* clean clip: `100 - 25 per false alarm`. A false alarm is any correction for a flaw the shooter doesn't have.
* no output, an error, a timeout or no shot detected: 0.

## Results file

`results/latest.json` (schema `schema_version: 1`) contains:

* `benchmark`: taxonomy, dataset and renderer hashes plus clip ids. Two runs are comparable only when these match.
* `run`: git sha, analyzer command and status (`ok | missing | build_failed | partial | failed`), per-clip status counts and `visual_evidence`.
* `summary`: overall, per-tier, per-view, flawed and clean scores; detection, advice and priority; false alarms.
* `flaws`: detection, advice and false-alarm rate for each flaw.
* `weakest`: flaws ranked by advice rate, over-called flaws, lowest tier, lowest clips. This answers "where is busk's advice weakest".
* `clips`: per clip score, labeled flaws, expected advice, what busk said, misses and false alarms.

`compare` flags a regression (exit 1) when the overall score drops more than 2 points, a tier drops more
than 5, a set (`synthetic`, `heldout`, `real`) drops more than 2, a flaw's advice rate drops more than 20 points,
or more clean clips get false alarms. Thresholds are flags (`--max-overall-drop`, `--max-tier-drop`,
`--max-set-drop`, `--max-flaw-drop`). Use `--json` or `--report FILE` to get
the comparison as JSON.

## Reference analyzers

`reference_analyzers/` holds three stand-ins that implement the contract. They are used to validate the
scorer and are not busk (scores on the core synthetic set, `--set synthetic`):

| analyzer | overall | beginner | intermediate | advanced | elite |
|---|---|---|---|---|---|
| `oracle.py` (reads the labels, upper bound) | 100.0 | 100.0 | 100.0 | 100.0 | 100.0 |
| `keypoint_heuristic.py` (rules on the keypoints) | 91.3 | 76.0 | 90.0 | 100.0 | 100.0 |
| `generic_tips.py` (same three tips for everyone) | 26.2 | 16.5 | 27.5 | 40.0 | 25.0 |

```bash
benchmark/run.sh --analyzer "python3 benchmark/reference_analyzers/keypoint_heuristic.py" --out /tmp/heuristic.json
```

## CI

`.github/workflows/shot-feedback-benchmark.yml` runs the benchmark on every push to `main`, on pull
requests and on manual dispatch. It runs on macOS so a Swift and Vision analyzer can build. It compares the
run with the last successful `main` run (or `baselines/main.json`), uploads `shot-feedback-results`
(`latest.json` plus `compare.json`) and writes a job summary. On a regression, or when the native
`busk-analyze` fails to build or run, the job fails. It also scores a fresh held-out draw seeded by the run id
and reports it next to the pinned held-out score (informational: a pinned score far above fresh draws means
the analyzer has been fitted to the pinned shooters).

## Visual evidence

Every run that counts needs screenshots and a recording of busk analysing the benchmark's clips. On a Mac
with busk installed in a booted simulator, add `--capture-simulator --require-visuals`. The run records
`results/visual/simulator.mp4` and, for every clip with keypoints, relaunches busk with
`-replay-keypoints <clip>.keypoints.json -replay-label <clip id>`. busk then plays that clip through its live
session (the same `ShotAnalyzer` and `FormEvaluator`), shows the cue and form card it gives, and the run
screenshots it. Paths are listed under `run.visual_evidence` and in each clip's `screenshot`. Attach them to
the PR or report. Real clips have no keypoints, so they are not replayed.

The capture picks the booted simulator that has busk (`com.potatoman03.busk`); `--simulator NAME|UDID` picks
one explicitly. With `--require-visuals` the run exits 3 unless busk analysed at least one clip and was still
running when the recording stopped.

## Limits

* The clips are synthetic. They test the coaching logic exactly and repeatably, not robustness to real
  phone footage (lighting, clutter, occlusion, camera angle). Real clips can be added later as another
  archetype source; their labels would need a coach's review.
* The advice regexes accept common phrasings of each fix. If busk words a correct fix in a way they miss,
  extend `fix_patterns` in `taxonomy.json`. That changes the taxonomy hash, so the next comparison is
  marked not comparable instead of reporting a fake regression.

## Real-footage tier

`benchmark/real_clips.json` adds real video next to the synthetic core: openly licensed clips from Wikimedia Commons, fetched at run time from their original URL and checked against the pinned SHA-1 (no footage is stored in this repo; each clip records its page, license and credit for attribution). Clips are cached in `benchmark/.cache/real/` and transcoded to MP4. Real clips get no keypoint sidecar, so the analyzer has to find the pose itself, as the app does.

| clip | tier | view | license | labels |
|---|---|---|---|---|
| Jackson McAndrew game free throw (upright phone video) | advanced | front | CC BY 4.0 | clean |
| Kobe Bryant warmup free throw (handheld fan video) | elite | front | CC BY 2.0 | clean |
| Marianna Tolo game free throw (from the stands) | elite | front | CC BY-SA 4.0 | clean |
| Research demo jump shot (PLOS ONE shot-type study) | advanced | side | CC BY 4.0 | clean |

`--set synthetic|real|all` picks the clips (default `all`); results carry `set` per clip and `set_scores`. A real clip that can't be fetched is skipped and listed in `run.real_unavailable` instead of failing the run.

Gaps: no openly licensed Steph Curry footage and no usable beginner shooting footage turned up on Commons, so the real tier only checks that good form isn't "corrected". Beginner fixes are covered by the synthetic set. Labels are one reviewer's judgement (`label_confidence` per clip).

## Held-out tier

The 28 core clips are the ones busk's thresholds were tuned against, so they saturate (busk scores ~99 on
them). The held-out tier scores shooters busk has never been tuned on: `busk_bench/heldout.py` draws 48 random
shooters (96 clips, side and front) from the ranges in [`heldout.json`](heldout.json): body height, tempo,
jump, handedness, look and any 0 to 4 flaws at random severities. Labels come from the taxonomy label rules
applied to the drawn parameters, and every range keeps a gap around its threshold so no label is borderline.
Severity (which flaw busk should mention first) follows how far past its threshold each flaw is.

Only the generator and ranges are checked in, not the shooters. The pinned `seed` keeps runs comparable
for CI; `--heldout-seed N` draws a new set, so a fitted analyzer can always be checked against shooters
nobody has looked at. Changing the seed, ranges or generator changes the dataset hash, so the next comparison
is marked not comparable.

`set_scores` reports each set and `generalization_gap` is the synthetic score minus the held-out score.

Native `busk-analyze` (main, pinned seed): synthetic 98.6, held-out 82.1, real 87.5 (gap +16.4); fresh seeds
1 to 3 score 88.5, 89.6, 89.7 on held-out. Simulating a regression by dropping busk's `hitch_at_set_point`
cue drops held-out 2.2 and fails the comparison.

## Running against busk's own analysis

The default analyzer is busk's native `busk-analyze` (`Tools/busk-analyze`, built from the app's own
`Busk/` sources by the root `Package.swift`). It uses the benchmark keypoints when given, and Vision pose
detection on the video otherwise, so real clips are scored too. `benchmark/run.sh` builds it first; no setup
is needed beyond Xcode or a Swift toolchain on macOS.
