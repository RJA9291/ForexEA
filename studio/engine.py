"""Auto Studio workflow engine.

A workflow (studio/workflows/<name>.yaml) is an ordered list of steps. The
engine runs `python` and `check` steps itself and stops at `claude` steps
(printing the instructions Claude must carry out) and `approval` steps (which
wait for the owner). State lives in studio/state/<name>.json so any run can be
resumed after a crash or on the next scheduled day.

Usage (from anywhere):
  python studio/engine.py status   [workflow]
  python studio/engine.py next     <workflow>
  python studio/engine.py done     <workflow> <step> [--set key=value ...]
  python studio/engine.py approve  <workflow>
  python studio/engine.py defer    <workflow> <step> <reason...>
  python studio/engine.py goto     <workflow> <step>
  python studio/engine.py new      <workflow> [--set key=value ...]
"""
import datetime as dt
import glob as globmod
import json
import subprocess
import sys
from pathlib import Path

import yaml

import steps as builtin

STUDIO = Path(__file__).resolve().parent
WORKFLOWS = STUDIO / "workflows"
STATE_DIR = STUDIO / "state"
MYT = dt.timezone(dt.timedelta(hours=8))

sys.stdout.reconfigure(encoding="utf-8")


def now():
    return dt.datetime.now(MYT)


def load_workflow(name):
    path = WORKFLOWS / f"{name}.yaml"
    if not path.exists():
        sys.exit(f"No workflow file: {path}")
    wf = yaml.safe_load(path.read_text(encoding="utf-8"))
    wf["root_path"] = (STUDIO / wf.get("root", "..")).resolve()
    ids = [s["id"] for s in wf["steps"]]
    if len(ids) != len(set(ids)):
        sys.exit(f"Duplicate step ids in {path.name}")
    return wf


def state_path(name):
    return STATE_DIR / f"{name}.json"


def load_state(name, wf):
    p = state_path(name)
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {"workflow": name, "ctx": dict(wf.get("init", {})), "step": 0, "status": "ready",
            "finished_on": None, "log": []}


def save_state(name, st):
    STATE_DIR.mkdir(exist_ok=True)
    st["log"] = st["log"][-200:]
    state_path(name).write_text(json.dumps(st, indent=2, ensure_ascii=False), encoding="utf-8")


def log(st, msg):
    line = f"{now():%Y-%m-%d %H:%M} {msg}"
    st["log"].append(line)
    print(line)


class Ctx(dict):
    def __missing__(self, key):
        raise KeyError(f"unknown variable {{{key}}}")


def context(wf, st):
    c = Ctx(wf.get("vars", {}))
    c.update(st["ctx"])
    c["root"] = str(wf["root_path"])
    c["today"] = now().date().isoformat()
    for k, v in list(c.items()):
        if isinstance(v, int) and not isinstance(v, bool):
            c[f"{k}2"] = f"{v:02d}"
            c[f"{k}_next"] = v + 1
    for k, fn in getattr(builtin, "DERIVED", {}).items():
        c[k] = fn(c)
    for _ in range(3):
        for k, v in list(c.items()):
            if isinstance(v, str) and "{" in v:
                c[k] = v.format_map(c)
    return c


def render(value, c):
    if isinstance(value, str):
        return value.format_map(c)
    if isinstance(value, list):
        return [render(v, c) for v in value]
    if isinstance(value, dict):
        return {k: render(v, c) for k, v in value.items()}
    return value


def abspath(wf, rel):
    p = Path(rel)
    return p if p.is_absolute() else wf["root_path"] / p


def all_exist(wf, paths):
    return all(abspath(wf, p).exists() for p in paths)


def run_python(wf, step, c, st):
    if "run" in step:
        cmd = render(step["run"], c)
        # Windows CreateProcess cannot launch a relative exe path written with forward slashes
        exe = abspath(wf, cmd[0])
        if exe.exists():
            cmd = [str(exe)] + list(cmd[1:])
        print(f"  $ {' '.join(cmd)}")
        r = subprocess.run(cmd, cwd=wf["root_path"], text=True, encoding="utf-8", errors="replace",
                           capture_output=True)
        out = (r.stdout or "") + (r.stderr or "")
        print("  " + out.strip().replace("\n", "\n  ")[-3000:])
        if r.returncode != 0:
            return f"exit code {r.returncode}"
        return None
    fn = getattr(builtin, step["call"])
    return fn(wf["root_path"], st, **render(step.get("args", {}), c))


def run_check(wf, step, c):
    files = render(step.get("files", []), c)
    missing = [f for f in files if not abspath(wf, f).exists()]
    if missing:
        return f"missing: {', '.join(missing)}"
    if "glob" in step:
        found = sorted(globmod.glob(str(abspath(wf, render(step["glob"], c)))))
        want_file, key = render(step["count_from_json"], c)
        want = len(json.loads(abspath(wf, want_file).read_text(encoding="utf-8"))[key])
        if len(found) != want:
            return f"{len(found)} files match {step['glob']}, expected {want}"
    return None


def instructions(wf, step, c):
    text = step.get("instructions", "")
    if "prompt" in step:
        text = (STUDIO / step["prompt"]).read_text(encoding="utf-8")
    return text.format_map(c)


def emit(kind, step, c, extra=None):
    print("\n=== " + kind + " ===")
    print(json.dumps({"step": step["id"], "type": step["type"], **(extra or {})}, ensure_ascii=False))
    if step.get("requires"):
        print("Files required before `done`: " + ", ".join(render(step["requires"], c)))


def cmd_next(name):
    wf = load_workflow(name)
    st = load_state(name, wf)
    if st["status"] == "done":
        if st["finished_on"] == now().date().isoformat() and not wf.get("allow_multiple_per_day"):
            print("Nothing to do: this workflow already finished a run today.")
            return
        start_new_run(wf, st)
    if st["status"] == "waiting_approval":
        step = wf["steps"][st["step"]]
        c = context(wf, st)
        emit("WAITING FOR OWNER APPROVAL", step, c, {"message": instructions(wf, step, c)})
        save_state(name, st)
        return
    while st["step"] < len(wf["steps"]):
        step = wf["steps"][st["step"]]
        c = context(wf, st)
        skip = render(step.get("skip_if_exists", []), c)
        if skip and all_exist(wf, skip):
            log(st, f"[{step['id']}] skipped (outputs already exist)")
            st["step"] += 1
            continue
        t = step["type"]
        if t in ("python", "check"):
            log(st, f"[{step['id']}] running")
            save_state(name, st)
            err = run_python(wf, step, c, st) if t == "python" else run_check(wf, step, c)
            if err:
                log(st, f"[{step['id']}] FAILED: {err}")
                back = step.get("on_fail")
                if back:
                    st["step"], st["status"] = [s["id"] for s in wf["steps"]].index(back), "running"
                    log(st, f"[{step['id']}] sent back to [{back}]; run `next` again")
                else:
                    st["status"] = "failed"
                save_state(name, st)
                sys.exit(1)
            log(st, f"[{step['id']}] ok")
            st["step"] += 1
            st["status"] = "running"
            save_state(name, st)
            continue
        if t == "claude":
            st["status"] = "waiting_claude"
            save_state(name, st)
            emit("CLAUDE STEP", step, c)
            print("\n" + instructions(wf, step, c))
            print(f"\nWhen finished: python studio/engine.py done {name} {step['id']}")
            return
        if t == "approval":
            st["status"] = "waiting_approval"
            log(st, f"[{step['id']}] waiting for owner approval")
            save_state(name, st)
            emit("WAITING FOR OWNER APPROVAL", step, c, {"message": instructions(wf, step, c)})
            return
        sys.exit(f"Unknown step type: {t}")
    finish_run(wf, st)
    save_state(name, st)


def start_new_run(wf, st):
    for k, v in wf.get("on_new_run", {}).get("increment", {}).items():
        st["ctx"][k] = st["ctx"].get(k, 0) + v
    st["step"], st["status"] = 0, "running"
    log(st, f"new run started: {json.dumps(st['ctx'], ensure_ascii=False)}")


def finish_run(wf, st):
    st["status"], st["finished_on"] = "done", now().date().isoformat()
    log(st, "run finished")


def current(name, step_id=None):
    wf = load_workflow(name)
    st = load_state(name, wf)
    if st["step"] >= len(wf["steps"]):
        sys.exit("No step in progress.")
    step = wf["steps"][st["step"]]
    if step_id and step["id"] != step_id:
        sys.exit(f"Current step is '{step['id']}', not '{step_id}'.")
    return wf, st, step


def parse_sets(args):
    out = {}
    for a in args:
        k, _, v = a.partition("=")
        out[k] = int(v) if v.lstrip("-").isdigit() else v
    return out


def cmd_done(name, step_id, sets):
    wf, st, step = current(name, step_id)
    if step["type"] != "claude":
        sys.exit(f"'{step_id}' is a {step['type']} step; it is not marked done by hand.")
    c = context(wf, st)
    missing = [f for f in render(step.get("requires", []), c) if not abspath(wf, f).exists()]
    if missing:
        sys.exit("Not done yet, missing: " + ", ".join(missing))
    st["ctx"].update(sets)
    st["step"] += 1
    st["status"] = "running"
    log(st, f"[{step_id}] done {json.dumps(sets, ensure_ascii=False) if sets else ''}".rstrip())
    if st["step"] >= len(wf["steps"]):
        finish_run(wf, st)
    save_state(name, st)


def cmd_approve(name):
    wf, st, step = current(name)
    if st["status"] != "waiting_approval":
        sys.exit(f"Nothing is waiting for approval (status: {st['status']}).")
    st["step"] += 1
    st["status"] = "running"
    log(st, f"[{step['id']}] approved by owner")
    save_state(name, st)


def cmd_defer(name, step_id, reason):
    wf, st, step = current(name, step_id)
    log(st, f"[{step_id}] deferred: {reason}")
    save_state(name, st)


def cmd_goto(name, step_id):
    wf = load_workflow(name)
    st = load_state(name, wf)
    ids = [s["id"] for s in wf["steps"]]
    if step_id not in ids:
        sys.exit(f"Unknown step. Steps: {', '.join(ids)}")
    st["step"], st["status"] = ids.index(step_id), "running"
    log(st, f"moved to step [{step_id}]")
    save_state(name, st)


def cmd_new(name, sets):
    wf = load_workflow(name)
    st = load_state(name, wf)
    st["ctx"].update(sets)
    st["step"], st["status"] = 0, "running"
    log(st, f"run (re)started: {json.dumps(st['ctx'], ensure_ascii=False)}")
    save_state(name, st)


def cmd_status(name=None):
    names = [name] if name else sorted(p.stem for p in WORKFLOWS.glob("*.yaml") if not p.stem.startswith("_"))
    for n in names:
        wf = load_workflow(n)
        st = load_state(n, wf)
        step = wf["steps"][st["step"]]["id"] if st["step"] < len(wf["steps"]) else "-"
        print(f"{n}: status={st['status']} step={step} ctx={json.dumps(st['ctx'], ensure_ascii=False)}")
        for line in st["log"][-8:]:
            print("   " + line)


def main(argv):
    if len(argv) < 1:
        sys.exit(__doc__)
    cmd, rest = argv[0], argv[1:]
    sets = []
    if "--set" in rest:
        i = rest.index("--set")
        rest, sets = rest[:i], rest[i + 1:]
    if cmd == "status":
        cmd_status(*rest[:1])
    elif cmd == "next" and len(rest) == 1:
        cmd_next(rest[0])
    elif cmd == "done" and len(rest) == 2:
        cmd_done(rest[0], rest[1], parse_sets(sets))
    elif cmd == "approve" and len(rest) == 1:
        cmd_approve(rest[0])
    elif cmd == "defer" and len(rest) >= 3:
        cmd_defer(rest[0], rest[1], " ".join(rest[2:]))
    elif cmd == "goto" and len(rest) == 2:
        cmd_goto(rest[0], rest[1])
    elif cmd == "new" and len(rest) == 1:
        cmd_new(rest[0], parse_sets(sets))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
