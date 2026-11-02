#!/usr/bin/env python3
"""Release guard: fail if game material or generated game code is tracked.

Run from the repository root, or from CI after checkout. It checks the files
Git knows about, so fetched third-party sources and ignored build outputs do
not trigger it.

Usage:
    python3 tools/check_no_game_data.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

FORBIDDEN_EXT = {
    ".iso", ".xex", ".pac", ".bik", ".ymk", ".ymb", ".pck", ".dds",
    ".apk", ".nro", ".nsp", ".xci", ".exe", ".dll", ".so", ".a", ".lib",
    ".obj", ".o", ".pdb", ".elf", ".zip", ".7z", ".rar", ".mp3", ".mp4",
    ".wav", ".flac", ".ogg", ".png", ".jpg", ".jpeg", ".bmp", ".gif",
    ".webp", ".svg", ".ttf", ".otf", ".ico",
}

FORBIDDEN_NAMES = {
    "default.xex",
    "svr2011.exe",
    "svr2011 launcher.exe",
    "svr2011 mod maker.exe",
    "svr2011 updater.exe",
    "libmain.so",
    "librexruntime.so",
    "librexgpu-xenos.so",
    "rexruntime.dll",
    "rexgpu-xenos.dll",
    "svr2011.apk",
}

FORBIDDEN_PARTS = {
    "native_shaders",
    "generated/default",
    "saves",
    "userdata",
    "mods",
    "dlc",
    "music",
    "custom movies",
    "texture packs",
    "texture dumps",
    "savebackups",
    "utilitydrive",
}

MAX_FILE_BYTES = 50 * 1024 * 1024
WARN_FILE_BYTES = 10 * 1024 * 1024


def tracked_files(root: Path) -> list[Path]:
    try:
        out = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=root, stderr=subprocess.DEVNULL
        )
        names = [n for n in out.decode("utf-8", "surrogateescape").split("\0") if n]
        return [root / n for n in names]
    except (OSError, subprocess.CalledProcessError):
        return [p for p in root.rglob("*") if p.is_file() and ".git" not in p.parts]


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    errors: list[str] = []
    warnings: list[str] = []

    files = tracked_files(root)
    if not files:
        print("warning: no tracked files found; run from a git checkout", file=sys.stderr)

    for path in files:
        rel = path.relative_to(root).as_posix()
        low = rel.lower()
        name = path.name.lower()
        suffix = path.suffix.lower()

        if suffix in FORBIDDEN_EXT:
            errors.append(f"forbidden extension: {rel}")
        if name in FORBIDDEN_NAMES:
            errors.append(f"forbidden file name: {rel}")
        for part in FORBIDDEN_PARTS:
            if f"/{part}/" in f"/{low}/":
                errors.append(f"forbidden path component '{part}': {rel}")
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size > MAX_FILE_BYTES:
            errors.append(f"file larger than 50 MB ({size} bytes): {rel}")
        elif size > WARN_FILE_BYTES:
            warnings.append(f"large file ({size} bytes): {rel}")

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)

    if errors:
        print(f"\nrelease guard failed: {len(errors)} error(s)", file=sys.stderr)
        return 1

    print(f"release guard OK: {len(files)} tracked files, no game material found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
