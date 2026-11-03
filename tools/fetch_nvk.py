#!/usr/bin/env python3
"""Fetch the pinned Mesa NVK archive for Nintendo Switch.

NVK is Mesa's Vulkan driver. The archive is a public, MIT-licensed build of
Mesa 25.0.7 for Horizon; it contains libvulkan.a, the Vulkan headers and the
driver's NOTICE. It contains no game code.

    python3 tools/fetch_nvk.py --dest third_party/nvk/extracted

The release URL and SHA-256 are pinned so a build uses the same driver.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

VERSION = "nvk-switch-mesa-25.0.7-r1"
URL = (
    "https://github.com/jhuz0/nvk-switch/releases/download/"
    f"{VERSION}/nvk-switch-25.0.7.tar.xz"
)
SHA256 = "4ab244f982dc078aaff8c58640d7cf8a0f3ab43bbf2daadfd00c02fbf352af86"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dest",
        default="third_party/nvk/extracted",
        help="where to extract the archive (default: third_party/nvk/extracted)",
    )
    parser.add_argument("--force", action="store_true", help="download again even if present")
    args = parser.parse_args()

    dest = Path(args.dest).resolve()
    lib = dest / "lib" / "libvulkan.a"
    if lib.is_file() and not args.force:
        print(f"NVK already present: {lib}")
        return 0

    dest.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nvk-switch-") as tmp:
        archive = Path(tmp) / "nvk-switch.tar.xz"
        print(f"downloading {URL}")
        with urllib.request.urlopen(URL, timeout=120) as response, archive.open("wb") as out:
            shutil.copyfileobj(response, out)
        got = sha256(archive)
        if got != SHA256:
            print(f"error: SHA-256 mismatch\n  expected {SHA256}\n  got      {got}", file=sys.stderr)
            return 1
        print(f"SHA-256 OK: {got}")
        print(f"extracting to {dest}")
        with tarfile.open(archive, "r:xz") as tar:
            tar.extractall(dest)

    if not lib.is_file():
        print(f"error: {lib} not found after extraction", file=sys.stderr)
        return 1
    print(f"done: {lib}")
    print("NVK is MIT-licensed; see NOTICE.md in the extracted folder.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
