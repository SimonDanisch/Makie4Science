"""Independent German word check with Desktop's existing Whisper checkpoint.

Recognizes the fitted audio, not the script. The hint contains only proper names.
ASR checks words, not acting, accent quality or voice consistency.
"""
import argparse
import json
import math
from pathlib import Path
import re
from difflib import SequenceMatcher

import numpy as np
from scipy.signal import resample_poly
import soundfile as sf
import torch
from transformers import pipeline


def words(text):
    return re.sub(r"[^\w\s]", " ", text.casefold()).split()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--ids", default="")
    args = ap.parse_args()
    rows = json.loads(args.manifest.read_text())
    selected = set(args.ids.split(",")) if args.ids else None
    snapshots = Path.home() / ".cache/huggingface/hub/models--openai--whisper-large-v3-turbo/snapshots"
    model = next(snapshots.iterdir())
    torch.set_num_threads(6)
    asr = pipeline("automatic-speech-recognition", model=str(model),
                   torch_dtype=torch.float16, device=0)
    names = "M87, Julia, Comrade, Photonenring, Wasserstoffmaser, Event Horizon Telescope."
    prompt = asr.tokenizer.get_prompt_ids(names, return_tensors="pt").to("cuda")
    report = args.manifest.with_name("word_check.json")
    checks = ([c for c in json.loads(report.read_text()) if c["id"] not in selected]
              if selected and report.exists() else [])
    for row in rows:
        if selected and row["id"] not in selected:
            continue
        audio, rate = sf.read(row["fitted"], dtype="float32")
        gcd = math.gcd(rate, 16000)
        audio = np.pad(resample_poly(audio, 16000//gcd, rate//gcd), (6400, 6400))
        result = asr({"raw": audio, "sampling_rate": 16000}, generate_kwargs={
            "language": "german", "task": "transcribe", "prompt_ids": prompt})
        text = result["text"].strip()
        check = dict(id=row["id"], expected=row["text"], recognized=text,
                     word_similarity=SequenceMatcher(None, words(row["text"]), words(text)).ratio())
        checks.append(check)
        report.write_text(json.dumps(checks, ensure_ascii=False, indent=2))
        print(json.dumps(check, ensure_ascii=False), flush=True)
    print(f"WORD_CHECK_COMPLETE {len(checks)} lines", flush=True)


if __name__ == "__main__":
    main()
