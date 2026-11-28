"""Move the newest image downloaded in the last few minutes into place.

Usage: python studio/grab_download.py <dest.png|dest.jpg> [max_age_minutes]
Converts with ffmpeg when the downloaded format differs from the destination.
"""
import subprocess
import sys
import time
from pathlib import Path

DOWNLOADS = Path.home() / "Downloads"
EXTS = {".png", ".jpg", ".jpeg", ".webp"}

dest = Path(sys.argv[1])
max_age = float(sys.argv[2]) if len(sys.argv) > 2 else 10
cutoff = time.time() - max_age * 60
files = [p for p in DOWNLOADS.iterdir() if p.suffix.lower() in EXTS and p.stat().st_mtime > cutoff]
if not files:
    sys.exit(f"No image downloaded in the last {max_age:g} minutes in {DOWNLOADS}")
src = max(files, key=lambda p: p.stat().st_mtime)
dest.parent.mkdir(parents=True, exist_ok=True)
if src.suffix.lower() == dest.suffix.lower() or {src.suffix.lower(), dest.suffix.lower()} == {".jpg", ".jpeg"}:
    src.replace(dest)
else:
    args = ["-q:v", "2"] if dest.suffix.lower() in (".jpg", ".jpeg") else []
    r = subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(src), *args, str(dest)], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr)
    src.unlink()
print(f"{src.name} -> {dest} ({dest.stat().st_size / 1e6:.1f} MB)")
