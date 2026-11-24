"""German VoxCPM2 narration, using existing Desktop weights; no image renderer.

Run with CrawCity's ~/tools/voxcpm/.venv/bin/python. The job JSON contains
translated lines and ORIGINAL line slots in seconds, supplied by voice_de.jl.
Raw takes, fitted takes and a manifest are retained. Atempo preserves pitch;
video is never opened by this program. Outputs are deliberately untracked.
"""
import argparse
import json
import math
import os
from pathlib import Path
import random
import subprocess
import time

import numpy as np
import soundfile as sf
import torch
from voxcpm import VoxCPM


VOICE = ("A native German woman in her thirties, warm clear mid-range voice, "
         "natural standard German pronunciation, curious and calm science "
         "documentary narrator, conversational, steady pace, no music")
DIRECTION = "Native standard German. Clear calm explanation, natural steady pace."
REFERENCE_TEXT = ("Wie fotografiert man etwas, das kein Licht aussendet? "
                  "Schauen wir uns an, wie Astronomen ein schwarzes Loch sichtbar machen.")


def trimmed(samples, rate):
    samples = np.asarray(samples, dtype=np.float32).reshape(-1)
    if not len(samples) or not np.isfinite(samples).all():
        raise ValueError("Empty or non-finite speech")
    block = max(1, round(rate * .01))
    active = [i for i in range(0, len(samples), block)
              if np.sqrt(np.mean(samples[i:i+block] ** 2)) > .003]
    if not active:
        raise ValueError("Silent speech")
    begin = max(0, active[0] - round(.035 * rate))
    end = min(len(samples), active[-1] + block + round(.08 * rate))
    return samples[begin:end]


def tempo_filter(ratio):
    factors = []
    while ratio > 2:
        factors.append(2)
        ratio /= 2
    while ratio < .5:
        factors.append(.5)
        ratio /= .5
    return ",".join(f"atempo={f:.8f}" for f in factors + [ratio])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("job", type=Path)
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    job = json.loads(args.job.read_text())
    args.out.mkdir(parents=True, exist_ok=True)
    raw_dir = args.out / "raw"
    fitted_dir = args.out / "fitted"
    raw_dir.mkdir(exist_ok=True)
    fitted_dir.mkdir(exist_ok=True)
    torch.set_num_threads(8)
    model = VoxCPM.from_pretrained(str(args.checkpoint), load_denoiser=False,
                                  optimize=False, device="cuda")
    rate = model.tts_model.sample_rate
    print(f"MODEL_READY {rate}Hz GPU={torch.cuda.memory_allocated()/2**30:.2f}GiB", flush=True)
    reference = args.out / "narrator_reference.wav"
    if not reference.exists():
        torch.manual_seed(8712)
        voice = model.generate(text=f"({VOICE}){REFERENCE_TEXT}", cfg_value=2.0,
                               inference_timesteps=10, max_len=400)
        sf.write(reference, trimmed(voice, rate), rate, subtype="PCM_24")
    manifest = []
    only = set(args.only.split(",")) if args.only else None
    total = len(job["lines"])
    for i, line in enumerate(job["lines"]):
        key = line["id"]
        if only and key not in only:
            continue
        raw = raw_dir / (key + ".wav")
        fitted = fitted_dir / (key + ".wav")
        meta = raw_dir / (key + ".json")
        target = line["end"] - line["start"]
        if target <= 0:
            raise ValueError(f"Invalid line slot: {key}")
        signature = dict(text=line["text"], seed=11000+i, steps=10,
                         direction=DIRECTION, voice=VOICE)
        started = time.monotonic()
        if raw.exists():
            if not meta.exists() or json.loads(meta.read_text()) != signature:
                raise ValueError(f"Existing take has a different script/settings: {key}")
            samples, actual_rate = sf.read(raw, dtype="float32")
            assert actual_rate == rate
        else:
            random.seed(signature["seed"])
            np.random.seed(signature["seed"])
            torch.manual_seed(signature["seed"])
            samples = model.generate(text=f"({DIRECTION}){line['text']}",
                                     reference_wav_path=str(reference), cfg_value=2.0,
                                     inference_timesteps=10, max_len=400)
            samples = trimmed(samples, rate)
            sf.write(raw, samples, rate, subtype="PCM_24")
            meta.write_text(json.dumps(signature, ensure_ascii=False, indent=2))
        natural = len(samples)/rate
        ratio = natural/target
        # Keep the original cue slots, with no audio crossing into the next cue.
        filters = tempo_filter(ratio) + f",apad,atrim=duration={target:.9f}"
        subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                        "-i", str(raw), "-af", filters, "-ar", str(rate), "-ac", "1",
                        "-c:a", "pcm_s24le", str(fitted)], check=True)
        entry = dict(line, natural_seconds=natural, slot_seconds=target,
                     tempo=ratio, raw=str(raw), fitted=str(fitted))
        manifest.append(entry)
        (args.out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        print(f"LINE {i+1}/{total} {key} natural={natural:.2f}s slot={target:.2f}s "
              f"tempo={ratio:.3f} wall={time.monotonic()-started:.1f}s", flush=True)
    if only:
        return
    track = np.zeros(round(job["duration"] * rate), dtype=np.float32)
    for line in manifest:
        samples, actual_rate = sf.read(line["fitted"], dtype="float32")
        assert actual_rate == rate
        start = round(line["start"] * rate)
        n = min(len(samples), len(track)-start, round(line["slot_seconds"] * rate))
        # Short fades suppress splice clicks; no global time stretch.
        fade = min(round(.008*rate), n//2)
        samples[:fade] *= np.linspace(0, 1, fade)
        samples[n-fade:n] *= np.linspace(1, 0, fade)
        track[start:start+n] += samples[:n]
    peak = float(np.max(np.abs(track)))
    if peak > .95:
        track *= .95/peak
    assert np.isfinite(track).all()
    sf.write(args.out / "narration_de.wav", track, rate, subtype="PCM_24")
    print(f"GERMAN_AUDIO_COMPLETE duration={len(track)/rate:.3f}s lines={total} peak={peak:.3f}", flush=True)


if __name__ == "__main__":
    main()
