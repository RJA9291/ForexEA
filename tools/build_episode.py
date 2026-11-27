"""Build a finished episode video from scene images + Kokoro voiceover parts.

Usage (from the series folder):
  ..\\tools\\kokoro\\.venv\\Scripts\\python ..\\tools\\build_episode.py ep01-edit.json

The config lists scenes in order; each scene starts at <offset> seconds into
voiceover part <part>. Every scene is cut into 6-9 s "shots" with slow zoom/pan
moves toward the focus points, so no still image sits unchanged on screen.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import soundfile as sf

FPS = 30
W, H = 1920, 1080
SHOT_TARGET_S = 7.5
FADE_S = 0.35
END_FADE_S = 1.2
FONT = "C\\:/Windows/Fonts/impact.ttf"


def run(cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"FAILED: {' '.join(map(str, cmd))}\n{r.stderr[-2000:]}")
    return r


def clamp_expr(f, axis):
    dim = "iw" if axis == "x" else "ih"
    return f"max(0,min({dim}-{dim}/zoom,{f}*{dim}-{dim}/zoom/2))"


def motion(kind, n, focus):
    p = f"(on/{max(n - 1, 1)})"
    center_x, center_y = clamp_expr(0.5, "x"), clamp_expr(0.5, "y")
    if kind == "wide_in":
        return f"1+0.10*{p}", center_x, center_y
    if kind == "wide_out":
        return f"1.14-0.12*{p}", center_x, center_y
    if kind == "pan_lr":
        return "1.18", f"(iw-iw/zoom)*{p}", center_y
    if kind == "pan_rl":
        return "1.18", f"(iw-iw/zoom)*(1-{p})", center_y
    fx, fy = focus
    return f"1.28+0.14*{p}", clamp_expr(fx, "x"), clamp_expr(fy, "y")


def shot_kinds(count, n_focus):
    base = ["wide_in", "F0", "pan_lr", "F1", "wide_out", "F2", "pan_rl", "F3"]
    kinds, i = [], 0
    while len(kinds) < count:
        k = base[i % len(base)]
        if k.startswith("F"):
            if n_focus == 0:
                k = "wide_in"
            else:
                k = f"F{int(k[1:]) % n_focus}"
        kinds.append(k)
        i += 1
    return kinds


def speech_segments(wav, min_gap):
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(wav), "-af", f"silencedetect=noise=-45dB:d={min_gap}", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", r.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", r.stderr)]
    total = sf.info(str(wav)).duration
    segs, cur = [], 0.0
    for s, e in zip(starts, ends):
        if s - cur > 0.15:
            segs.append((cur, s))
        cur = e
    if total - cur > 0.15:
        segs.append((cur, total))
    return segs


def chunk_words(text, max_words=6):
    words, chunks, cur = text.split(), [], []
    for w in words:
        cur.append(w)
        if len(cur) >= max_words or (len(cur) >= 3 and w[-1] in ".,?!:;\"”"):
            chunks.append(" ".join(cur))
            cur = []
    if cur:
        if chunks and len(cur) <= 2:
            chunks[-1] += " " + " ".join(cur)
        else:
            chunks.append(" ".join(cur))
    return chunks


def ts_ass(t):
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return f"{int(h)}:{int(m):02d}:{s:05.2f}"


def ts_srt(t):
    ms = int(round(t * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def main():
    cfg_path = Path(sys.argv[1]).resolve()
    root = cfg_path.parent
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    audio_dir, image_dir = root / cfg["audio_dir"], root / cfg["image_dir"]
    build = root / cfg.get("build_dir", "build")
    (build / "clips").mkdir(parents=True, exist_ok=True)

    parts = sorted(audio_dir.glob("part*.wav"))
    durs = [sf.info(str(p)).duration for p in parts]
    gap = cfg["part_gap"]
    part_start, t = [], 0.0
    for d in durs:
        part_start.append(t)
        t += d + gap
    audio_end = sf.info(str(audio_dir / "full.wav")).duration
    end_card_s = cfg.get("end_card_seconds", 3.0)

    scenes = cfg["scenes"]
    starts = [part_start[s["part"] - 1] + s.get("offset", 0.0) for s in scenes]
    bounds = [round(x * FPS) for x in starts] + [round(audio_end * FPS)]

    # ---- video clips ----
    clip_list = []
    for i, sc in enumerate(scenes):
        total = bounds[i + 1] - bounds[i]
        n_shots = max(1, round(total / (SHOT_TARGET_S * FPS)))
        lens = [total // n_shots] * n_shots
        lens[-1] += total - sum(lens)
        kinds = shot_kinds(n_shots, len(sc.get("focus", [])))
        if n_shots == 1 and sc.get("focus"):
            kinds = ["F0"]
        next_hard = i + 1 < len(scenes) and scenes[i + 1].get("cut") == "hard"
        img = image_dir / sc["image"]
        for j, (n, kind) in enumerate(zip(lens, kinds)):
            focus = sc["focus"][int(kind[1:])] if kind.startswith("F") else None
            z, x, y = motion(kind, n, focus)
            vf = [
                f"scale={W * 2}:{H * 2}:flags=lanczos,setsar=1",
                f"zoompan=z='{z}':x='{x}':y='{y}':d={n}:s={W}x{H}:fps={FPS}",
            ]
            if j == 0 and i > 0 and sc.get("cut") != "hard":
                vf.append(f"fade=t=in:st=0:d={FADE_S}")
            if j == n_shots - 1:
                if i == len(scenes) - 1:
                    vf.append(f"fade=t=out:st={n / FPS - END_FADE_S:.3f}:d={END_FADE_S}")
                elif not next_hard:
                    vf.append(f"fade=t=out:st={n / FPS - FADE_S:.3f}:d={FADE_S}")
            vf.append("format=yuv420p")
            key = hashlib.sha1(f"{img}|{img.stat().st_mtime_ns}|{n}|{','.join(vf)}".encode()).hexdigest()[:10]
            out = build / "clips" / f"s{i + 1:02d}_{j:02d}_{key}.mp4"
            if not out.exists():
                run(["ffmpeg", "-y", "-v", "error", "-i", str(img), "-vf", ",".join(vf), "-frames:v", str(n),
                     "-r", str(FPS), "-c:v", "libx264", "-preset", "veryfast", "-crf", "17", str(out)])
            clip_list.append(out)
        print(f"scene {i + 1:02d}: {total / FPS:6.1f}s in {n_shots} shots")

    # end card
    end_clip = build / "clips" / "zz_end.mp4"
    title, sub = cfg.get("end_title", "DAY 2"), cfg.get("end_subtitle", "COMING SOON")
    run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", f"color=c=black:s={W}x{H}:r={FPS}:d={end_card_s}",
         "-vf", f"drawtext=fontfile='{FONT}':text='{title}':fontcolor=0xE02020:fontsize=170:x=(w-tw)/2:y=(h-th)/2-70,"
                f"drawtext=fontfile='{FONT}':text='{sub}':fontcolor=white:fontsize=70:x=(w-tw)/2:y=(h/2)+90,"
                f"fade=t=in:st=0:d=0.6,format=yuv420p",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "17", str(end_clip)])
    clip_list.append(end_clip)
    for stale in (build / "clips").glob("*.mp4"):
        if stale not in clip_list:
            stale.unlink()

    (build / "list.txt").write_text("".join(f"file '{c.as_posix()}'\n" for c in clip_list), encoding="utf-8")
    run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", "list.txt", "-c", "copy", "video.mp4"], cwd=build)

    # ---- audio: voice + low freezer hum in chosen scenes ----
    total_s = audio_end + end_card_s
    hum_ranges = [(starts[i], (starts[i + 1] if i + 1 < len(scenes) else audio_end))
                  for i, s in enumerate(scenes) if s.get("hum")]
    on = "+".join(f"between(t,{a:.2f},{b:.2f})" for a, b in hum_ranges) or "0"
    filt = (
        f"anoisesrc=color=brown:amplitude={cfg.get('hum_amplitude', 0.04)}:sample_rate=24000:duration={total_s:.2f},"
        f"lowpass=f=160,lowpass=f=160,volume=0:enable='not({on})'[hum];"
        f"[0:a]apad=whole_dur={total_s:.2f}[v];"
        f"[v][hum]amix=inputs=2:normalize=0:duration=first,loudnorm=I=-15:TP=-1.5:LRA=11,aresample=48000[a]"
    )
    run(["ffmpeg", "-y", "-v", "error", "-i", str(audio_dir / "full.wav"), "-filter_complex", filt,
         "-map", "[a]", "-c:a", "pcm_s16le", "audio.wav"], cwd=build)

    # ---- captions from paragraph timing ----
    raw = (root / cfg["parts_file"]).read_text(encoding="utf-8")
    chunks = re.split(r"^===== PART (\d+).*?=====\s*$", raw, flags=re.M)[1:]
    caps = []
    for k in range(0, len(chunks), 2):
        num, body = int(chunks[k]), chunks[k + 1]
        paras = [p.strip() for p in body.strip().split("\n\n") if p.strip() and not p.strip().startswith("Gambar:")]
        segs = speech_segments(audio_dir / f"part{num:02d}.wav", 0.6)
        if len(segs) != len(paras):
            print(f"  part{num:02d}: {len(segs)} speech blocks vs {len(paras)} paragraphs, timing spread evenly")
            d = durs[num - 1]
            weights = [len(p) for p in paras]
            acc, segs = 0.0, []
            for w in weights:
                seg = d * w / sum(weights)
                segs.append((acc, acc + seg))
                acc += seg
        for para, (a, b) in zip(paras, segs):
            pieces = chunk_words(para.replace("\n", " "))
            weights = [len(c) + 2 for c in pieces]
            t0 = part_start[num - 1] + a
            span = b - a
            for c, w in zip(pieces, weights):
                dt = span * w / sum(weights)
                caps.append((t0, t0 + dt, c))
                t0 += dt

    ass = [
        "[Script Info]", "ScriptType: v4.00+", f"PlayResX: {W}", f"PlayResY: {H}", "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, "
        "Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Cap,Arial Black,64,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,5,1,2,80,80,90,1",
        "", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    srt = []
    for n, (a, b, c) in enumerate(caps, 1):
        ass.append(f"Dialogue: 0,{ts_ass(a)},{ts_ass(b)},Cap,,0,0,0,,{c}")
        srt.append(f"{n}\n{ts_srt(a)} --> {ts_srt(b)}\n{c}\n")
    (build / "captions.ass").write_text("\n".join(ass) + "\n", encoding="utf-8")
    out_name = cfg["output"]
    (root / Path(out_name).with_suffix(".srt")).write_text("\n".join(srt), encoding="utf-8")

    # ---- final render ----
    vf = "ass=captions.ass" if cfg.get("burn_captions", True) else "null"
    run(["ffmpeg", "-y", "-v", "error", "-i", "video.mp4", "-i", "audio.wav", "-vf", vf,
         "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", str(root / out_name)], cwd=build)
    print(f"done: {out_name}  ({len(clip_list)} clips, {len(caps)} captions)")


if __name__ == "__main__":
    main()
