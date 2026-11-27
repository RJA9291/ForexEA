"""Built-in python steps and derived variables for Auto Studio workflows.

A step with `call: <name>` runs fn(root, state, **args) and returns None on
success or an error string. DERIVED maps a variable name to fn(ctx) -> value.
"""
import datetime as dt
import shutil
import subprocess
from pathlib import Path


def compress_if_large(root, state, src, max_mb=250, crf=23):
    """Re-encode the video in place when it is too big to upload within an hour."""
    path = root / src
    if not path.exists():
        return f"missing {src}"
    size_mb = path.stat().st_size / 1e6
    if size_mb <= float(max_mb):
        print(f"  {path.name}: {size_mb:.0f} MB, no compression needed")
        return None
    tmp = path.with_name(path.stem + ".compressing.mp4")
    r = subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(path), "-c:v", "libx264", "-preset", "medium",
                        "-crf", str(crf), "-c:a", "copy", "-movflags", "+faststart", str(tmp)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        tmp.unlink(missing_ok=True)
        return r.stderr[-1500:]
    shutil.move(tmp, path)
    print(f"  {path.name}: {size_mb:.0f} MB -> {path.stat().st_size / 1e6:.0f} MB")
    return None


def _publish_date(c):
    tomorrow = dt.date.fromisoformat(c["today"]) + dt.timedelta(days=1)
    last = c.get("last_publish_date")
    if last:
        tomorrow = max(tomorrow, dt.date.fromisoformat(last) + dt.timedelta(days=1))
    return tomorrow.isoformat()


DERIVED = {"publish_date": _publish_date}
