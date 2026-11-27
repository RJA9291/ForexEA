"""Generate voiceover WAVs from an Episode-XX-Voiceover-Parts.txt file with Kokoro.

Usage:
  .venv/Scripts/python gen_episode.py <parts.txt> <out_dir> [voice] [speed]
"""
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = Path(__file__).parent
PARAGRAPH_GAP_S = 0.6
PART_GAP_S = 1.2

parts_file, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
voice = sys.argv[3] if len(sys.argv) > 3 else "bm_george"
speed = float(sys.argv[4]) if len(sys.argv) > 4 else 0.95
lang = "en-gb" if voice.startswith("b") else "en-us"

kokoro = Kokoro(str(HERE / "models" / "kokoro-v1.0.onnx"), str(HERE / "models" / "voices-v1.0.bin"))
out_dir.mkdir(parents=True, exist_ok=True)

raw = parts_file.read_text(encoding="utf-8")
chunks = re.split(r"^===== PART (\d+).*?=====\s*$", raw, flags=re.M)[1:]
parts = [(int(chunks[i]), chunks[i + 1]) for i in range(0, len(chunks), 2)]

full, sr = [], None
for num, body in parts:
    paragraphs = [p.strip() for p in body.strip().split("\n\n")]
    paragraphs = [p for p in paragraphs if p and not p.startswith("Gambar:")]
    audio = []
    for p in paragraphs:
        samples, sr = kokoro.create(p, voice=voice, speed=speed, lang=lang)
        audio += [samples, np.zeros(int(sr * PARAGRAPH_GAP_S), dtype=samples.dtype)]
    part_audio = np.concatenate(audio)
    path = out_dir / f"part{num:02d}.wav"
    sf.write(path, part_audio, sr)
    print(f"{path.name}: {len(part_audio) / sr:6.1f}s")
    full += [part_audio, np.zeros(int(sr * PART_GAP_S), dtype=part_audio.dtype)]

full_audio = np.concatenate(full)
sf.write(out_dir / "full.wav", full_audio, sr)
mins, secs = divmod(len(full_audio) / sr, 60)
print(f"full.wav: {int(mins)}m {secs:.0f}s")
