import json
import sys
import tempfile
import unittest
from pathlib import Path

BENCH = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BENCH))

from busk_bench.analyzer import resolve_command  # noqa: E402
from busk_bench.cli import compare_docs  # noqa: E402
from busk_bench.dataset import load_clips, load_taxonomy  # noqa: E402
from busk_bench.kinematics import ShotParams  # noqa: E402
from busk_bench.scoring import score_clip, summarize  # noqa: E402
from busk_bench.visual import pick_device  # noqa: E402

TAX = load_taxonomy()
CLIPS, _, _ = load_clips(TAX)
OPS = {"<": lambda a, b: a < b, ">": lambda a, b: a > b}


def perfect(clip, ids=True):
    fb = [TAX.flaws[f["id"]].canonical_fix for f in clip.observable] or ["Great shot, textbook."]
    shot = {"feedback": fb}
    if ids:
        shot["flaws"] = [f["id"] for f in clip.observable]
    return {"shots": [shot]}


class Labels(unittest.TestCase):
    def test_labels_follow_taxonomy_rules(self):
        raw = json.loads((BENCH / "clips.json").read_text())
        for a in raw["archetypes"]:
            p = ShotParams.from_dict(a["params"])
            want = {fid for fid, f in TAX.flaws.items()
                    if OPS[f.label_rule["op"]](p.value(f.label_rule["param"]), f.label_rule["value"])}
            self.assertEqual({f["id"] for f in a["flaws"]}, want, a["id"])

    def test_tiers_span_beginner_to_elite(self):
        tiers = {c.tier for c in CLIPS}
        self.assertEqual(tiers, {"beginner", "intermediate", "advanced", "elite"})
        self.assertTrue(all(not c.flaws for c in CLIPS if c.tier == "elite"))
        self.assertTrue(all(len(c.flaws) >= 3 for c in CLIPS if c.tier == "beginner"))

    def test_view_filtering(self):
        side = next(c for c in CLIPS if c.id == "beginner_chest_push__side")
        self.assertNotIn("elbow_flare", [f["id"] for f in side.observable])
        self.assertIn("elbow_flare", [f["id"] for f in side.flaws])


class Scoring(unittest.TestCase):
    def test_perfect_feedback_scores_100(self):
        for c in CLIPS:
            self.assertEqual(score_clip(c, perfect(c), TAX)["score"], 100.0, c.id)

    def test_text_only_feedback_scores_100(self):
        for c in CLIPS:
            self.assertEqual(score_clip(c, perfect(c, ids=False), TAX)["score"], 100.0, c.id)

    def test_tip_on_clean_form_is_a_false_alarm(self):
        c = next(c for c in CLIPS if c.id == "elite_curry_one_motion__side")
        r = score_clip(c, {"shots": [{"feedback": ["Tuck your elbow in under the ball."]}]}, TAX)
        self.assertEqual(r["false_alarms"], ["elbow_flare"])
        self.assertEqual(r["score"], 75.0)

    def test_praise_is_not_a_false_alarm(self):
        c = next(c for c in CLIPS if c.id == "elite_klay_textbook__front")
        r = score_clip(c, {"shots": [{"feedback": ["Great follow-through, beautiful arc!"]}]}, TAX)
        self.assertEqual(r["score"], 100.0)

    def test_no_output_and_no_shot_score_zero(self):
        c = CLIPS[0]
        self.assertEqual(score_clip(c, None, TAX)["score"], 0.0)
        self.assertEqual(score_clip(c, {"shots": []}, TAX)["status_reason"], "no_shot_detected")

    def test_naming_a_flaw_without_a_fix_gets_no_advice_credit(self):
        c = next(c for c in CLIPS if c.id == "rec_flat_shot__side")
        r = score_clip(c, {"shots": [{"flaws": ["flat_arc"], "feedback": ["Your shot is flat."]}]}, TAX)
        self.assertEqual(r["detection"], 1.0)
        self.assertEqual(r["advice"], 0.0)

    def test_summary_finds_weakest_flaw(self):
        res = {}
        for c in CLIPS:
            out = perfect(c)
            out["shots"][0]["flaws"] = [f for f in out["shots"][0]["flaws"] if f != "flat_arc"]
            out["shots"][0]["feedback"] = [ln for ln in out["shots"][0]["feedback"] if "arc" not in ln.lower()]
            res[c.id] = score_clip(c, out, TAX)
        s = summarize(CLIPS, res, TAX)
        self.assertEqual(s["weakest"]["flaws_by_advice"][0]["flaw"], "flat_arc")


class Compare(unittest.TestCase):
    def _doc(self, scale):
        res = {c.id: score_clip(c, perfect(c), TAX) for c in CLIPS}
        for c in CLIPS:
            res[c.id].update(clip=c.id)
            if c.tier == "beginner":
                res[c.id]["score"] *= scale
        doc = summarize(CLIPS, res, TAX)
        doc.update(benchmark={"taxonomy_sha256": "t", "dataset_sha256": "d", "clip_ids": [c.id for c in CLIPS]},
                   run={"git_sha": str(scale)}, clips=list(res.values()))
        return doc

    def test_drop_is_a_regression(self):
        rep = compare_docs(self._doc(1.0), self._doc(0.5))
        self.assertTrue(rep["comparable"])
        self.assertTrue(any("beginner" in r for r in rep["regressions"]))

    def test_same_run_is_clean(self):
        self.assertEqual(compare_docs(self._doc(1.0), self._doc(1.0))["regressions"], [])

    def test_changed_dataset_is_not_comparable(self):
        new = self._doc(0.5)
        new["benchmark"]["dataset_sha256"] = "other"
        rep = compare_docs(self._doc(1.0), new)
        self.assertFalse(rep["comparable"])
        self.assertEqual(rep["regressions"], [])


class Contract(unittest.TestCase):
    def test_missing_analyzer(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(resolve_command(None, Path(d)), (None, "not_found"))

    def test_swift_package_is_discovered(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "Package.swift").write_text('.executable(name: "busk-analyze", targets: ["BuskAnalyze"])')
            argv, src = resolve_command(None, Path(d))
            self.assertEqual(src, "Package.swift")
            self.assertIn("busk-analyze", argv)


class Render(unittest.TestCase):
    def test_render_is_deterministic(self):
        from busk_bench.render import render_clip
        c = next(c for c in CLIPS if c.id == "rec_lazy_finish__side")
        with tempfile.TemporaryDirectory() as d:
            render_clip(c.spec(), Path(d) / "a")
            render_clip(c.spec(), Path(d) / "b")
            ka = (Path(d) / "a" / f"{c.id}.keypoints.json").read_text()
            kb = (Path(d) / "b" / f"{c.id}.keypoints.json").read_text()
            self.assertEqual(ka, kb)
            self.assertGreater((Path(d) / "a" / f"{c.id}.mp4").stat().st_size, 10_000)


class RealTier(unittest.TestCase):
    def test_manifest_has_provenance_and_valid_labels(self):
        from busk_bench.real import load_real_clips
        clips, _, _ = load_real_clips(load_taxonomy())
        self.assertGreaterEqual(len(clips), 3)
        for c in clips:
            self.assertEqual(c.set, "real")
            self.assertTrue(c.id.startswith("real__"))
            self.assertRegex(c.source["sha1"], r"^[0-9a-f]{40}$")
            self.assertRegex(c.source["license"], r"^(CC BY|CC0|Public domain)")
            self.assertTrue(c.source["url"].startswith("https://upload.wikimedia.org/"))

    def test_download_verifies_sha1(self):
        import hashlib
        from busk_bench.real import download
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "clip.webm"
            src.write_bytes(b"not really a video")
            good = hashlib.sha1(src.read_bytes()).hexdigest()
            dest = Path(d) / "out.webm"
            download(src.as_uri(), dest, good, sleep=lambda s: None)
            self.assertEqual(dest.read_bytes(), src.read_bytes())
            with self.assertRaises(ValueError):
                download(src.as_uri(), Path(d) / "bad.webm", "0" * 40, sleep=lambda s: None)
            self.assertFalse((Path(d) / "bad.webm").exists())


if __name__ == "__main__":
    unittest.main()


class SimulatorPick(unittest.TestCase):
    A = {"udid": "A", "name": "iPhone 17"}
    B = {"udid": "B", "name": "iPhone 17 Pro"}

    def test_prefers_the_simulator_running_busk(self):
        self.assertEqual(pick_device([self.A, self.B], "booted", {"B": True}), ("B", None))

    def test_single_booted_simulator(self):
        self.assertEqual(pick_device([self.A], "booted", {}), ("A", None))

    def test_ambiguous_without_busk_is_an_error(self):
        udid, err = pick_device([self.A, self.B], "booted", {})
        self.assertIsNone(udid)
        self.assertIn("--simulator", err)

    def test_explicit_device_by_name_or_udid(self):
        self.assertEqual(pick_device([self.A, self.B], "iPhone 17 Pro", {}), ("B", None))
        self.assertEqual(pick_device([self.A, self.B], "A", {}), ("A", None))
        self.assertIsNotNone(pick_device([self.A], "C", {})[1])

    def test_nothing_booted(self):
        self.assertIsNotNone(pick_device([], "booted", {})[1])
