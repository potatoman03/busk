"""Real-footage tier: openly licensed clips fetched by URL, verified against a pinned SHA-1, transcoded to MP4."""
from __future__ import annotations

import hashlib
import json
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from .dataset import BENCH_DIR, Clip, Taxonomy, _sha

REAL_PATH = BENCH_DIR / "real_clips.json"
USER_AGENT = "busk-bench/1.0 (+https://github.com/potatoman03/busk; shooting-feedback benchmark)"
REQUIRED_SOURCE = ("page", "url", "sha1", "license", "credit")


def load_real_clips(tax: Taxonomy, path: Path = REAL_PATH) -> tuple[list[Clip], str, str]:
    raw = json.loads(path.read_text())
    order = {fid: i for i, fid in enumerate(tax.flaws)}
    clips = []
    for r in raw["clips"]:
        missing = [k for k in REQUIRED_SOURCE if not r.get("source", {}).get(k)]
        if missing:
            raise ValueError(f"{r['id']}: source is missing {missing}")
        for f in r["flaws"]:
            if f["id"] not in tax.flaws:
                raise ValueError(f"{r['id']}: unknown flaw {f['id']}")
        obs = [f for f in r["flaws"] if r["view"] in tax.flaws[f["id"]].views]
        obs.sort(key=lambda f: (-f["severity"], order[f["id"]]))
        clips.append(Clip(
            id=f"real__{r['id']}__{r['view']}", archetype=f"real__{r['id']}", tier=r["tier"], view=r["view"],
            handedness=r["handedness"], description=r["description"], params={}, look={},
            flaws=r["flaws"], observable=obs, set="real", source=r["source"],
        ))
    return clips, raw["version"], _sha(path)


def _sha1(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def download(url: str, dest: Path, sha1: str, tries: int = 6, sleep=time.sleep) -> None:
    last = None
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            got = hashlib.sha1(data).hexdigest()
            if got != sha1:
                raise ValueError(f"sha1 mismatch for {url}: expected {sha1}, got {got}")
            tmp = dest.with_name(dest.name + ".part")
            tmp.write_bytes(data)
            tmp.replace(dest)
            return
        except ValueError:
            raise
        except urllib.error.HTTPError as e:
            last = e
            sleep(min(60, 5 * 2 ** k) if e.code == 429 else 3)
        except Exception as e:  # network errors: retry
            last = e
            sleep(3)
    raise RuntimeError(f"could not fetch {url}: {last}")


def fetch(clip: Clip, cache: Path, log) -> Path:
    """Return a cached MP4 of the clip, downloading and verifying the original if needed."""
    src = clip.source
    d = cache / "real"
    d.mkdir(parents=True, exist_ok=True)
    orig = d / (src["sha1"] + Path(src["url"]).suffix)
    if not orig.exists() or _sha1(orig) != src["sha1"]:
        log(f"fetching {clip.id} ({src['license']}, {src['credit']}) from {src['page']}")
        download(src["url"], orig, src["sha1"])
    mp4 = d / f"{src['sha1']}.720p30.mp4"
    if not mp4.exists():
        import imageio_ffmpeg
        tmp = d / f"{src['sha1']}.tmp.mp4"
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(orig), "-an",
                        "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,fps=30",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast", "-crf", "18", str(tmp)],
                       check=True)
        tmp.replace(mp4)
    return mp4
