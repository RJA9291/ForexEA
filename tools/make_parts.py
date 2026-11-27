"""Turn an Episode-XX-Script.md into the files the pipeline needs.

Usage: python make_parts.py <Episode-XX-Script.md> <episode_number>

Writes next to the script:
  Episode-XX-Voiceover-Parts.txt  one PART per [SCENE] (read by gen_episode.py)
  Episode-XX-Image-Prompts.md     one prompt per scene, numbered to match
  epXX-edit.json                  build config for build_episode.py (one scene per part)
"""
import json
import re
import sys
from pathlib import Path

script = Path(sys.argv[1])
ep = int(sys.argv[2])
root = script.parent

scenes, cur, desc = [], [], None
for line in script.read_text(encoding="utf-8").splitlines():
    s = line.strip()
    if s.startswith("[SCENE"):
        if desc is not None:
            scenes.append((desc, "\n".join(cur).strip()))
        desc, cur = s[len("[SCENE:"):].rstrip("]").strip(), []
        continue
    if s.startswith(("#", "**", "---", "*End", ">")) or desc is None:
        continue
    cur.append(line)
if desc is not None:
    scenes.append((desc, "\n".join(cur).strip()))

problems = [i + 1 for i, (_, body) in enumerate(scenes) if not body]
if problems:
    sys.exit(f"Scenes with no narration (merge or add text): {problems}")
digits = sorted({m for _, body in scenes for m in re.findall(r"\S*\d\S*", body)})
if digits:
    print("WARNING digits left in narration (TTS may misread):", digits)

parts = []
for i, (d, body) in enumerate(scenes, 1):
    body = re.sub(r"\n{3,}", "\n\n", body)
    parts.append(f"===== PART {i:02d} ({len(body)} chars) =====\nGambar: {d}\n\n{body}\n")
(root / f"Episode-{ep:02d}-Voiceover-Parts.txt").write_text("\n".join(parts), encoding="utf-8")

prompts = [f"# Episode {ep}: Prompt Gambar Scene ({len(scenes)} gambar)\n",
           "Guna chat ChatGPT yang sama dengan episod sebelum ini (Mesej Setup dari Episode-01-Image-Prompts.md "
           "sudah dihantar). Kalau chat baru, hantar Mesej Setup itu dulu dan upload logo.\n",
           f"Simpan sebagai `scene01.png` sampai `scene{len(scenes):02d}.png` dalam folder `images-ep{ep:02d}/`.\n"]
for i, (d, _) in enumerate(scenes, 1):
    prompts.append(f"### Scene {i}\n```\nScene {i}. {d}. No blood, and no text other than anything described above.\n```\n")
(root / f"Episode-{ep:02d}-Image-Prompts.md").write_text("\n".join(prompts), encoding="utf-8")

cfg_path = root / f"ep{ep:02d}-edit.json"
if not cfg_path.exists():
    cfg = {
        "audio_dir": f"audio-ep{ep:02d}", "image_dir": f"images-ep{ep:02d}",
        "parts_file": f"Episode-{ep:02d}-Voiceover-Parts.txt", "build_dir": f"build-ep{ep:02d}",
        "output": f"TheLastShift-S01E{ep:02d}.mp4", "part_gap": 1.2,
        "end_title": f"DAY {ep + 1}", "end_subtitle": "COMING SOON", "end_card_seconds": 3.0,
        "hum_amplitude": 0.04, "burn_captions": True,
        "scenes": [{"image": f"scene{i:02d}.png", "part": i, "hum": True, "focus": []}
                   for i in range(1, len(scenes) + 1)],
    }
    cfg_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")

words = sum(len(b.split()) for _, b in scenes)
print(f"{len(scenes)} scenes, {words} words")
