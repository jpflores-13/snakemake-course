#!/usr/bin/env python3
"""Pre-render step: run real commands and save their output under _generated/.

Quarto runs this before every project render (`pre-render` in _quarto.yml).
Pages show the results with the {{< generated name="..." >}} shortcode.

What it runs:

1. Dry runs of the lab pipelines (git submodules under pipelines/) against the
   dry-run fixtures each pipeline ships in tests/dryrun/: `snakemake -n`,
   `--dag`, `--rulegraph` and `--list-rules`.
2. The same for RegPipe (course-pipeline/), once data/samplesheet.txt exists.
3. Every `<!-- GENERATE: name | cwd | command -->` comment found in
   lessons/*.qmd, answers/*.qmd, exercises/*.qmd, field-guide/*.qmd and the
   top-level pages. `cwd` is relative to the course root; everything after
   the second ` | ` is the command (so it may contain pipes).

Each command runs in a scratch copy of its folder (so no .snakemake/ or
output/ is left behind and earlier runs never change the result), with data/
and the other course folders linked in. Absolute scratch paths are rewritten
to relative ones before saving.

Outputs:
  _generated/<name>.txt   stdout + stderr of a normal command
  _generated/<name>.dot   stdout of a --dag / --rulegraph command
  _generated/<name>.svg   that graph drawn with Graphviz `dot`, if available
  _generated/manifest.json  command, folder, exit code and input hash per name

A command is re-run only when its inputs change (the hash in the manifest).
A failure is logged and the render goes on. If a command that used to
succeed now fails (for example because data/ is missing on this machine), the
earlier output is kept.

Environment variables:
  COURSE_SKIP_GENERATE=1   do nothing (CI renders the committed outputs)
  COURSE_FORCE_GENERATE=1  ignore the cache and re-run everything
  COURSE_GENERATE_ONLY=a,b only these names
  COURSE_EXTRA_PATH=dir:dir  prepended to PATH for every command (tool envs)
  COURSE_GENERATE_TIMEOUT=600  seconds per command
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

VERSION = "1"  # bump to invalidate every cached output
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "_generated"
MANIFEST = OUT / "manifest.json"
TIMEOUT = int(os.environ.get("COURSE_GENERATE_TIMEOUT", "600"))

# folders never copied into a scratch run (and ignored when hashing)
SKIP_NAMES = {".git", ".snakemake", "output", "output_ci", "output_test", "results",
              "__pycache__", ".pytest_cache", "_site", ".quarto", "_freeze", "_generated"}
# top-level entries never linked into the scratch course root
SKIP_TOP = {".git", "_site", ".quarto", "_freeze", "_generated", ".github"}

GENERATE_RE = re.compile(r"<!--\s*GENERATE:\s*(.*?)\s*-->", re.S)
GRAPH_RE = re.compile(r"--(dag|rulegraph|filegraph|d3dag)\b")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
PAGE_GLOBS = ["*.qmd", "lessons/*.qmd", "answers/*.qmd", "exercises/*.qmd", "field-guide/*.qmd"]


def log(msg: str) -> None:
    print(f"[generate] {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# tools
# ---------------------------------------------------------------------------

def find_tool(name: str, extra: list[str]) -> str | None:
    hit = shutil.which(name)
    if hit:
        return hit
    for cand in extra:
        if os.access(cand, os.X_OK):
            return cand
    return None


SNAKEMAKE = find_tool("snakemake", ["/opt/course-venv/bin/snakemake"])
DOT = find_tool("dot", ["/opt/mamba/envs/graphviz/bin/dot", "/opt/homebrew/bin/dot", "/usr/local/bin/dot"])


def run_env() -> dict:
    env = dict(os.environ)
    parts = [p for p in os.environ.get("COURSE_EXTRA_PATH", "").split(os.pathsep) if p]
    if SNAKEMAKE:
        parts.append(str(Path(SNAKEMAKE).parent))
    env["PATH"] = os.pathsep.join(parts + [env.get("PATH", "")])
    env.setdefault("LC_ALL", "C.UTF-8")
    env["TERM"] = "dumb"
    env["NO_COLOR"] = "1"
    return env


# ---------------------------------------------------------------------------
# hashing
# ---------------------------------------------------------------------------

def tree_hash(path: Path, h, with_content: bool = True) -> None:
    """Feed the file names (and contents, or sizes) under `path` into hash `h`."""
    if not path.exists():
        h.update(f"missing:{path.name}".encode())
        return
    if path.is_file():
        h.update(path.name.encode())
        h.update(path.read_bytes() if with_content else str(path.stat().st_size).encode())
        return
    for dirpath, dirnames, filenames in os.walk(path):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_NAMES)
        for fn in sorted(filenames):
            fp = Path(dirpath) / fn
            rel = fp.relative_to(path).as_posix()
            h.update(rel.encode())
            try:
                if with_content and fp.stat().st_size < 2_000_000:
                    h.update(fp.read_bytes())
                else:
                    h.update(str(fp.stat().st_size).encode())
            except OSError:
                pass


def git_state(path: Path) -> str:
    """Commit + dirty state of a submodule checkout (fast stand-in for a tree hash)."""
    try:
        sha = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True,
                             text=True, timeout=30).stdout.strip()
        dirty = subprocess.run(["git", "-C", str(path), "status", "--porcelain"], capture_output=True,
                               text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return sha + hashlib.sha256(dirty.encode()).hexdigest() if sha else ""


def task_hash(task: dict) -> str:
    h = hashlib.sha256()
    h.update(f"{VERSION}\0{task['cwd']}\0{task['command']}\0".encode())
    cwd = ROOT / task["cwd"]
    top = Path(task["cwd"]).parts[0] if task["cwd"] not in ("", ".") else ""
    if top == "pipelines":
        state = git_state(cwd)
        if state:
            h.update(state.encode())
        else:
            tree_hash(cwd, h)
    elif top:
        tree_hash(ROOT / top, h)
    # data/: names and sizes only (the FASTQs are large)
    tree_hash(ROOT / "data", h, with_content=False)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# task list
# ---------------------------------------------------------------------------

def sm(*args: str) -> str:
    return "snakemake " + " ".join(args)


def pipeline_tasks() -> list[dict]:
    """Dry runs of the lab pipelines against their own shipped fixtures."""
    tasks: list[dict] = []

    def add(prefix: str, cwd: str, base: str, kinds=("dryrun", "dag", "rulegraph", "list-rules")):
        flags = {"dryrun": "-n", "dag": "--dag", "rulegraph": "--rulegraph", "list-rules": "--list-rules"}
        for k in kinds:
            tasks.append({"name": f"{prefix}-{k}", "cwd": cwd, "command": f"{sm(flags[k])} {base}",
                          "source": "_scripts/generate.py"})

    mc = "pipelines/microcpipe"
    if (ROOT / mc / "tests/dryrun/config.yaml").exists():
        # as in MicroCPipe's tests/test_dryrun.py
        add("microcpipe", mc, "-s workflows/MicroCPipe.snakefile --cores 1 "
                               "--configfile config/MicroCConfig.yaml tests/dryrun/config.yaml")
        add("microcpipe-merge", mc, "-s workflows/MicroCMerge.snakefile --cores 1 "
                                     "--configfile config/MicroCConfig.yaml tests/dryrun/config.yaml",
            kinds=("dryrun", "rulegraph"))
    tt = "pipelines/ttpipe"
    if (ROOT / tt / "tests/dryrun/config.yaml").exists():
        # as in TTpipe's tests/test_dryrun.py
        add("ttpipe", tt, "-s workflows/TTpipe.snakefile --cores 1 "
                          "--configfile config/TTpipeConfig.yaml tests/dryrun/config.yaml")
    cs = "pipelines/chromsimpipe"
    if (ROOT / cs / "workflows/ChromSimPipe.snakefile").exists():
        # ChromSimConfig.test.yaml points at genome and peak files under data/ that are
        # not in the repository, so a dry run stops with MissingInputException. Keep
        # the rule list, and that real error message (useful when teaching it).
        base = "-s workflows/ChromSimPipe.snakefile --cores 1 --configfile config/ChromSimConfig.test.yaml"
        tasks.append({"name": "chromsimpipe-list-rules", "cwd": cs, "command": f"{sm('--list-rules')} {base}",
                      "source": "_scripts/generate.py"})
        tasks.append({"name": "chromsimpipe-missing-input", "cwd": cs, "command": f"{sm('-n')} {base}",
                      "source": "_scripts/generate.py", "expect_fail": True})
    return tasks


def regpipe_tasks() -> list[dict]:
    cp = ROOT / "course-pipeline"
    snakefile = cp / "workflows/RegPipe.snakefile"
    if not (cp.is_dir() and (ROOT / "data/samplesheet.txt").exists() and snakefile.exists()):
        return []
    base = "-s workflows/RegPipe.snakefile --cores 1"
    if (cp / "config/RegConfig.yaml").exists():
        base += " --configfile config/RegConfig.yaml"
    flags = {"dryrun": "-n", "dryrun-p": "-n -p", "dag": "--dag", "rulegraph": "--rulegraph",
             "list-rules": "--list-rules", "summary": "--summary"}
    return [{"name": f"regpipe-{k}", "cwd": "course-pipeline", "command": f"{sm(f)} {base}",
             "source": "_scripts/generate.py"} for k, f in flags.items()]


def comment_tasks() -> list[dict]:
    tasks = []
    seen: dict[str, str] = {}
    for pattern in PAGE_GLOBS:
        for page in sorted(ROOT.glob(pattern)):
            text = page.read_text(encoding="utf-8", errors="replace")
            for m in GENERATE_RE.finditer(text):
                parts = [p.strip() for p in m.group(1).split("|", 2)]
                rel = page.relative_to(ROOT).as_posix()
                if len(parts) != 3 or not all(parts):
                    log(f"{rel}: cannot parse GENERATE comment: {m.group(0)[:80]}")
                    continue
                name, cwd, command = parts
                if not NAME_RE.match(name):
                    log(f"{rel}: bad output name {name!r} (letters, digits, - _ . only)")
                    continue
                cwd = cwd.strip("/") or "."
                if cwd.startswith("..") or Path(cwd).is_absolute():
                    log(f"{rel}: cwd must be inside the course folder: {cwd}")
                    continue
                if name in seen and seen[name] != f"{cwd}|{command}":
                    log(f"{rel}: name {name!r} already used with a different command in {seen[name + '@']}")
                    continue
                if name in seen:
                    continue
                seen[name] = f"{cwd}|{command}"
                seen[name + "@"] = rel
                tasks.append({"name": name, "cwd": cwd, "command": command, "source": rel})
    return tasks


# ---------------------------------------------------------------------------
# running
# ---------------------------------------------------------------------------

def ignore_copy(_dir, names):
    return [n for n in names if n in SKIP_NAMES]


def make_sandbox(cwd_rel: str) -> tuple[Path, Path]:
    """Scratch course root: every top-level entry linked, the cwd's folder copied."""
    tmp = Path(tempfile.mkdtemp(prefix="course-gen-"))
    sandbox = tmp / "course"
    sandbox.mkdir()
    parts = Path(cwd_rel).parts if cwd_rel not in ("", ".") else ()
    for entry in ROOT.iterdir():
        if entry.name in SKIP_TOP:
            continue
        if parts and entry.name == parts[0]:
            continue
        (sandbox / entry.name).symlink_to(entry)
    if parts:
        src, dst = ROOT, sandbox
        for i, part in enumerate(parts):
            src, dst = src / part, dst / part
            if i == len(parts) - 1:
                if not src.is_dir():
                    raise FileNotFoundError(f"{cwd_rel} is not a folder")
                shutil.copytree(src, dst, symlinks=True, ignore=ignore_copy)
            else:
                dst.mkdir()
                for sib in src.iterdir():
                    if sib.name != parts[i + 1] and sib.name not in SKIP_NAMES:
                        (dst / sib.name).symlink_to(sib)
    return tmp, sandbox / Path(*parts) if parts else sandbox


def clean_text(text: str, cwd: Path, sandbox_root: Path) -> str:
    """Rewrite scratch and machine-specific paths so the output reads like a learner's run."""
    reps = [(str(cwd) + "/", ""), (str(cwd), "."),
            (str(sandbox_root) + "/", ""), (str(sandbox_root), "."),
            (str(ROOT) + "/", ""), (str(ROOT), ".")]
    for real in {cwd.resolve(), sandbox_root.resolve()}:
        reps += [(str(real) + "/", ""), (str(real), ".")]
    home = str(Path.home())
    for old, new in reps:
        text = text.replace(old, new)
    if home not in ("/", ""):
        text = text.replace(home + "/", "~/")
    out = []
    for line in text.splitlines():
        if re.match(r"^host: \S+$", line):  # machine name; not part of the lesson
            continue
        line = re.sub(r"\x1b\[[0-9;]*m", "", line)
        out.append(line.rstrip())
    return "\n".join(out).strip("\n") + "\n"


def draw(dot_path: Path, svg_path: Path) -> bool:
    if not DOT:
        return False
    try:
        r = subprocess.run([DOT, "-Tsvg", str(dot_path), "-o", str(svg_path)], capture_output=True,
                           text=True, timeout=120)
    except (OSError, subprocess.SubprocessError) as e:
        log(f"dot failed for {dot_path.name}: {e}")
        return False
    if r.returncode != 0:
        log(f"dot failed for {dot_path.name}: {r.stderr.strip()[:200]}")
        return False
    # drop the comment with the Graphviz version so re-drawing does not churn git
    svg = re.sub(r"<!-- Generated by graphviz.*?-->\n?", "", svg_path.read_text(), flags=re.S)
    svg_path.write_text(svg)
    return True


def run_task(task: dict) -> dict | None:
    name = task["name"]
    try:
        tmp, cwd = make_sandbox(task["cwd"])
    except (OSError, FileNotFoundError) as e:
        log(f"{name}: cannot prepare {task['cwd']}: {e}")
        return None
    sandbox_root = tmp / "course"
    t0 = time.time()
    try:
        # graphs: keep stdout (the dot text) apart from the log; everything else: one
        # interleaved stream, the way it appears in a terminal
        graph = GRAPH_RE.search(task["command"]) is not None
        r = subprocess.run(["bash", "-c", task["command"]], cwd=cwd, env=run_env(), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE if graph else subprocess.STDOUT, text=True, timeout=TIMEOUT)
        rc, stdout, stderr = r.returncode, r.stdout, r.stderr or ""
    except subprocess.TimeoutExpired as e:
        rc, stdout, stderr = 124, (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), \
            f"timed out after {TIMEOUT} s"
    except OSError as e:
        rc, stdout, stderr = 127, "", str(e)
    elapsed = time.time() - t0
    try:
        stdout_c = clean_text(stdout, cwd, sandbox_root)
        combined = clean_text(stdout + ("\n" if stdout and stderr else "") + stderr, cwd, sandbox_root) \
            if (stdout or stderr) else ""
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    lead = stdout.lstrip()
    if rc == 0 and lead.startswith(("digraph", "graph ", "strict digraph")):
        kind, body = "dot", stdout_c
    elif rc == 0 and lead.startswith(("<?xml", "<svg")):
        kind, body = "svg", stdout_c
    else:
        kind, body = "txt", combined
    return {"kind": kind, "body": body, "returncode": rc, "seconds": round(elapsed, 1)}


def write_output(name: str, result: dict) -> list[str]:
    for ext in ("txt", "dot", "svg"):
        p = OUT / f"{name}.{ext}"
        if p.exists():
            p.unlink()
    files = []
    target = OUT / f"{name}.{result['kind']}"
    target.write_text(result["body"], encoding="utf-8")
    files.append(target.name)
    if result["kind"] == "dot" and draw(target, OUT / f"{name}.svg"):
        files.append(f"{name}.svg")
    return files


def main() -> int:
    if os.environ.get("COURSE_SKIP_GENERATE") == "1":
        log("COURSE_SKIP_GENERATE=1: using the committed outputs in _generated/")
        return 0
    OUT.mkdir(exist_ok=True)
    try:
        manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    except (OSError, json.JSONDecodeError):
        manifest = {}
    force = os.environ.get("COURSE_FORCE_GENERATE") == "1"
    only = {n for n in os.environ.get("COURSE_GENERATE_ONLY", "").split(",") if n}

    tasks = pipeline_tasks() + regpipe_tasks()
    builtin = {t["name"] for t in tasks}
    for t in comment_tasks():
        if t["name"] in builtin:
            log(f"{t['source']}: {t['name']!r} is a built-in output name; pick another")
            continue
        tasks.append(t)

    if not SNAKEMAKE:
        log("snakemake not found on PATH or in /opt/course-venv/bin; snakemake commands will fail")
    if not DOT:
        log("Graphviz `dot` not found: graphs are saved as .dot only")

    ran = skipped = failed = 0
    for task in tasks:
        name = task["name"]
        if only and name not in only:
            continue
        digest = task_hash(task)
        old = manifest.get(name, {})
        have = [f for f in old.get("files", []) if (OUT / f).exists()]
        if not force and old.get("hash") == digest and have:
            # redraw a graph if dot became available since
            if old.get("kind") == "dot" and DOT and not (OUT / f"{name}.svg").exists():
                if draw(OUT / f"{name}.dot", OUT / f"{name}.svg"):
                    old["files"] = sorted(set(have) | {f"{name}.svg"})
            skipped += 1
            continue
        log(f"{name}: {task['command']}  (in {task['cwd']})")
        try:
            result = run_task(task)
        except Exception as e:  # never break the render
            log(f"{name}: unexpected error: {e!r}")
            result = None
        if result is None:
            failed += 1
            continue
        ok = result["returncode"] == 0
        expected_ok = not task.get("expect_fail")
        if ok != expected_ok:
            failed += 1
            log(f"{name}: exit code {result['returncode']} ({result['seconds']} s); "
                + (result["body"].strip().splitlines() or [""])[-1][:160])
            old_ok = (old.get("returncode") == 0) == expected_ok
            if have and old_ok:
                log(f"{name}: keeping the earlier output")
                continue
        files = write_output(name, result)
        manifest[name] = {"command": task["command"], "cwd": task["cwd"], "source": task["source"],
                          "returncode": result["returncode"], "kind": result["kind"], "files": files,
                          "hash": digest}
        ran += 1

    # forget outputs whose GENERATE comment is gone (files are left for the integrator)
    current = {t["name"] for t in tasks}
    for name in sorted(set(manifest) - current):
        if not only:
            log(f"{name}: no longer requested by any page (files left in _generated/)")
            manifest[name]["stale"] = True
    for name in current & set(manifest):
        manifest[name].pop("stale", None)

    MANIFEST.write_text(json.dumps(dict(sorted(manifest.items())), indent=2) + "\n")
    log(f"done: {ran} run, {skipped} cached, {failed} with problems")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # never fail the render
        log(f"stopped early: {e!r}")
        sys.exit(0)
