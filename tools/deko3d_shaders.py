#!/usr/bin/env python3
"""Build the deko3d shader pack from the native renderer's SPIR-V pack.

    SPIRV_CROSS=/path/to/spirv-cross python tools/deko3d_shaders.py \
        <native_shaders folder with shaders.spv.pak> [out folder]

For every ``<hash>.<vs|ps>[.s1|.s2].spv`` in ``shaders.spv.pak`` it runs
SPIRV-Cross to Vulkan GLSL, converts that to deko3d GLSL with
``tools/deko3d_glsl.py``, and wraps it in the ``Deko3DShaderBlob`` that
plume's deko3d back end expects (``BDK3``, stage, GLSL size, 0). The result is
``shaders.dk.pak`` next to the input pack, plus the shared ``.inputs`` /
``.textures`` files.

The native renderer's own shaders (present, debug, FSR) read their texture
indices from the renderer's own constants rather than the game's shared
constants; they are reported and skipped here, not guessed at.
"""

from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BLOB_MAGIC = 0x334B4442  # "BDK3"
STAGE = {"vs": 0, "ps": 4}  # DkStage_Vertex / DkStage_Fragment


def unpack(pak: Path, out: Path) -> list[str]:
    data = pak.read_bytes()
    if data[:8] != b"SVRPAK1\0":
        raise SystemExit(f"{pak}: not a shader pack")
    count = struct.unpack_from("<I", data, 8)[0]
    at = 12
    names = []
    out.mkdir(parents=True, exist_ok=True)
    for _ in range(count):
        length = struct.unpack_from("<H", data, at)[0]
        at += 2
        name = data[at:at + length].decode("utf-8")
        at += length
        offset, size = struct.unpack_from("<II", data, at)
        at += 8
        (out / name).write_bytes(data[offset:offset + size])
        names.append(name)
    return names


def pack(folder: Path, ext: str) -> Path:
    files = sorted(f for f in folder.iterdir()
                   if f.is_file() and (f.suffix == ext or f.suffix in (".inputs", ".textures")))
    if not any(f.suffix == ext for f in files):
        raise SystemExit(f"{folder}: no {ext} files")
    names = [f.name.encode() for f in files]
    header = 12 + sum(2 + len(n) + 8 for n in names)
    index = b""
    blobs = []
    offset = header
    for f, n in zip(files, names):
        data = f.read_bytes()
        index += struct.pack("<H", len(n)) + n + struct.pack("<II", offset, len(data))
        blobs.append(data)
        offset += len(data)
    out = folder / f"shaders{ext}.pak"
    tmp = out.with_suffix(".tmp")
    with open(tmp, "wb") as w:
        w.write(b"SVRPAK1\0" + struct.pack("<I", len(files)) + index)
        for b in blobs:
            w.write(b)
    tmp.replace(out)
    print(f"{out.name}: {len(files)} files, {offset // 1024} KB")
    return out


def stage_of(name: str) -> str | None:
    for s in ("vs", "ps"):
        if f".{s}." in name:
            return s
    return None


def main(args: list[str]) -> int:
    if not args:
        print(__doc__)
        return 2
    src = Path(args[0])
    out = Path(args[1]) if len(args) > 1 else src / "deko3d"
    spirv_cross = os.environ.get("SPIRV_CROSS", "spirv-cross")
    pak = src / "shaders.spv.pak"
    if not pak.exists():
        print(f"{pak}: missing (build the SPIR-V pack first)", file=sys.stderr)
        return 1
    names = unpack(pak, out / "spv")
    converted = skipped = 0
    for name in names:
        if not name.endswith(".spv"):
            continue
        stage = stage_of(name)
        if not stage:
            continue
        spv = out / "spv" / name
        base = name[:-4]  # without .spv
        glsl_vk = out / f"{base}.vk.glsl"
        glsl_dk = out / f"{base}.dk"
        r = subprocess.run([spirv_cross, str(spv), "--version", "460", "--vulkan-semantics",
                            "--relax-nan-checks"], capture_output=True, text=True)
        if r.returncode:
            print(f"{name}: spirv-cross failed: {r.stderr.strip()[:200]}", file=sys.stderr)
            skipped += 1
            continue
        glsl_vk.write_text(r.stdout, encoding="utf-8")
        r = subprocess.run([sys.executable, str(ROOT / "deko3d_glsl.py"), str(glsl_vk),
                            str(glsl_dk), "--stage", "vert" if stage == "vs" else "frag"],
                           capture_output=True, text=True)
        if r.returncode:
            print(f"{name}: {r.stderr.strip()[:240]}", file=sys.stderr)
            skipped += 1
            continue
        glsl = glsl_dk.read_bytes()
        blob = struct.pack("<IIII", BLOB_MAGIC, STAGE[stage], len(glsl), 0) + glsl
        glsl_dk.write_bytes(blob)
        converted += 1
    # The shared vertex-input and texture-slot lists stay as they are.
    for name in names:
        if name.endswith((".inputs", ".textures")):
            (out / name).write_bytes((out / "spv" / name).read_bytes())
    print(f"deko3d shaders: {converted} converted, {skipped} skipped")
    pack(out, ".dk")
    return 0 if converted else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
