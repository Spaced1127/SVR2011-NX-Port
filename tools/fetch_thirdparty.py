#!/usr/bin/env python3
"""Fetch the ReXGlue third-party sources into sdk/thirdparty.

The repository tracks only the third-party files this port changed. Everything
else is fetched locally from the upstream ReXGlue SDK at the commit the port is
based on (v0.10.0), including its submodules. The fetched tree is ignored by
git; each project keeps its own licence.

Usage:
    python3 tools/fetch_thirdparty.py

Needs git and network access.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

UPSTREAM = "https://github.com/rexglue/rexglue-sdk.git"
COMMIT = "c94f5ebdcb3c9d1a460ca48e04f9758448f8d518"  # v0.10.0


def run(*args: str, cwd: Path | None = None) -> None:
    print(">", " ".join(args), flush=True)
    subprocess.run(args, cwd=cwd, check=True)


def _remove_readonly(func, path, _exc):
    try:
        os.chmod(path, stat.S_IWRITE)
    except OSError:
        pass
    func(path)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    target = root / "sdk" / "thirdparty"
    target.mkdir(parents=True, exist_ok=True)

    # A quick completeness check. fmt and glslang are good canaries.
    if (target / "fmt").is_dir() and (target / "glslang").is_dir():
        print(f"third-party tree already present in {target}")
        return 0

    work = Path(tempfile.mkdtemp(prefix="rexglue-thirdparty-"))
    try:
        run("git", "init", "-q", str(work))
        run("git", "remote", "add", "origin", UPSTREAM, cwd=work)
        run("git", "fetch", "-q", "--depth", "1", "origin", COMMIT, cwd=work)
        run("git", "checkout", "-q", "FETCH_HEAD", cwd=work)
        run("git", "submodule", "update", "--init", "--recursive", cwd=work)

        source = work / "thirdparty"
        if not source.is_dir():
            print("error: upstream has no thirdparty directory", file=sys.stderr)
            return 1

        copied = kept = 0
        for src in source.rglob("*"):
            if not src.is_file():
                continue
            rel = src.relative_to(source)
            if ".git" in rel.parts:
                continue
            dst = target / rel
            if dst.exists():
                kept += 1
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            copied += 1

        print(f"{copied} files copied into {target}, {kept} existing files kept")
        return 0
    finally:
        shutil.rmtree(work, onexc=_remove_readonly)


if __name__ == "__main__":
    raise SystemExit(main())
