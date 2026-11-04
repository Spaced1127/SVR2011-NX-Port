#!/usr/bin/env python3
"""Turn the native renderer's Vulkan GLSL (SPIRV-Cross output) into deko3d GLSL.

    python tools/deko3d_glsl.py in.vk.glsl out.glsl --stage vert|frag

The native renderer's converted game shaders use:

  - a ByteAddressBuffer ``g_ConstantBuffer`` (set 2, binding 0) holding the
    frame's vertex, pixel and shared constants;
  - a push-constant block with the byte offsets of those three constants and
    the renderer's own constants;
  - two descriptor tables, ``g_Texture2DDescriptorHeap`` (set 0, binding 0)
    and ``g_SamplerDescriptorHeap`` (set 1, binding 0), whose entries are the
    game's texture and sampler indices.

deko3d's back end (plume_deko3d) binds textures per draw from the words in
the shared constants.  This tool emits that layout:

  - ``g_ConstantBuffer`` -> storage buffer binding 0;
  - the push block -> a std140 UBO at binding 5;
  - each texture/sampler pair read from the shared constants ->
    ``layout(binding = K) uniform sampler2D dk_tex_bK;`` and a ``texb=``
    entry (K:texture byte offset:sampler byte offset) in the ``banjo-dk``
    line that the back end parses.

It is deliberately limited to what the native renderer's shaders use.  An
unsupported construct is reported, never guessed at.
"""

from __future__ import annotations

import argparse
import re
import sys

PUSH_UBO_BINDING = 5
SHARED_WORD = re.compile(
    r"g_ConstantBuffer\._m0\[(?:\(\s*g_PushConstants\.SharedConstants\s*\+\s*(\d+)u?\s*\)|"
    r"g_PushConstants\.SharedConstants)\s*>>\s*2u\]"
)
TEMP_SHARED = re.compile(
    r"^\s*uint\s+(_\d+)\s*=\s*(?:\(\s*g_PushConstants\.SharedConstants\s*\+\s*(\d+)u?\s*\)|"
    r"g_PushConstants\.SharedConstants)\s*>>\s*2u;\s*$",
    re.M,
)
# The same for the renderer's own constants (the present / FSR shaders): the
# value is a real index into the texture and sampler tables, not an offset.
TEMP_OWN = re.compile(
    r"^\s*uint\s+(_\d+)\s*=\s*(?:\(\s*g_PushConstants\.OwnConstants\s*\+\s*(\d+)u?\s*\)|"
    r"g_PushConstants\.OwnConstants)\s*>>\s*2u;\s*$",
    re.M,
)
# g_ConstantBuffer._m0[_123] where _123 is a word index computed from the
# shared constants (the form SPIRV-Cross emits when a fetch is used more than
# once).
TEMP_WORD = re.compile(r"g_ConstantBuffer\._m0\[\s*([A-Za-z_]\w*)\s*\]")
# The game shaders' tables: 2D (set 0 binding 0), 3D (binding 1) and cube
# (binding 2), each addressed from 0 in Vulkan. deko3d's image descriptor set
# is one table, so the renderer writes global indices for it (SharedConstants).
TEXTURE_HEAPS = {
    "sampler2D": ("g_Texture2DDescriptorHeap", 0),
    "sampler3D": ("g_Texture3DDescriptorHeap", 1),
    "samplerCube": ("g_TextureCubeDescriptorHeap", 2),
}
TEXTURE_HEAP_OF = {name: stype for stype, (name, _) in TEXTURE_HEAPS.items()}

# Extensions SPIRV-Cross emits for Vulkan constructs the converted GLSL no
# longer uses (uam's frontend does not know some of them).
DROPPED_EXTENSIONS = (
    "GL_EXT_nonuniform_qualifier",
    "GL_EXT_samplerless_texture_functions",
    "GL_EXT_spirv_intrinsics",
    "GL_EXT_scalar_block_layout",
)


def heap_decl(name: str) -> re.Pattern[str]:
    return re.compile(
        rf"^layout\(set\s*=\s*0,\s*binding\s*=\s*\d+\)\s*uniform\s+texture\w+\s+"
        rf"{name}\s*\[\s*\d*\s*\];\s*$",
        re.M,
    )


TEX_DECLS = [(stype, name, heap_decl(name)) for stype, (name, _) in TEXTURE_HEAPS.items()]
SMP_DECL = re.compile(
    r"^layout\(set\s*=\s*1,\s*binding\s*=\s*0\)\s*uniform\s+sampler\s+"
    r"g_SamplerDescriptorHeap\s*\[\s*\d*\s*\];\s*$",
    re.M,
)
SAMPLER_CTOR = re.compile(
    r"sampler2D\(\s*g_Texture2DDescriptorHeap\s*\[(.*?)\]\s*,\s*"
    r"g_SamplerDescriptorHeap\s*\[(.*?)\]\s*\)",
    re.S,
)
TEXTURE_ONLY = re.compile(r"g_Texture2DDescriptorHeap\s*\[(.*?)\]", re.S)
INPUT_DECL = re.compile(r"^layout\(location\s*=\s*(\d+)\)\s*in\s+([^;]+);\s*$", re.M)
UNIFORM_DECL = re.compile(r"^layout\(([^)]*)\)\s*uniform\s+(?!sampler)\w", re.M)
BUFFER_DECL = re.compile(r"^layout\(([^)]*)\)\s*(?:readonly\s+|writeonly\s+|restrict\s+)*buffer\s", re.M)


class Unsupported(Exception):
    pass


def matching(text: str, at: int, open_ch: str, close_ch: str) -> int:
    depth = 0
    for i in range(at, len(text)):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i
    raise Unsupported(f"unbalanced {open_ch}{close_ch}")


def shared_offset(expr: str, temps: dict[str, int]) -> int | None:
    expr = expr.strip()
    m = SHARED_WORD.fullmatch(expr)
    if m:
        return int(m.group(1) or 0)
    m = TEMP_WORD.fullmatch(expr)
    if m and m.group(1) in temps:
        return temps[m.group(1)]
    if expr in temps:
        return temps[expr]
    return None


def word_source(expr: str, temps: dict[str, int], own: dict[str, int]) -> tuple[str, int] | None:
    """Where a texture/sampler table index is read from: ("shared", byte
    offset) or ("own", byte offset); None if it is not a constant read."""
    expr = expr.strip()
    m = SHARED_WORD.fullmatch(expr)
    if m:
        return ("shared", int(m.group(1) or 0))
    m = TEMP_WORD.fullmatch(expr)
    if m:
        name = m.group(1)
        if name in temps:
            return ("shared", temps[name])
        if name in own:
            return ("own", own[name])
    if expr in temps:
        return ("shared", temps[expr])
    if expr in own:
        return ("own", own[expr])
    return None


def convert(src: str, stage: str) -> str:
    text = src.replace("\r\n", "\n")
    if not text.startswith("#version"):
        raise Unsupported("no #version line")

    temps = {m.group(1): int(m.group(2) or 0) for m in TEMP_SHARED.finditer(text)}
    own_temps = {m.group(1): int(m.group(2) or 0) for m in TEMP_OWN.finditer(text)}

    present = [(stype, name, rex) for stype, name, rex in TEX_DECLS if rex.search(text)]
    has_textures = bool(present)
    has_samplers = bool(SMP_DECL.search(text))
    if has_samplers and not has_textures:
        raise Unsupported("a sampler table without a texture table")
    for _, _, rex in present:
        text = rex.sub("", text)
    if has_samplers:
        text = SMP_DECL.sub("", text)

    # set 2 binding 0 -> binding 0 (deko3d buffer binding space)
    text = re.sub(r"layout\(set\s*=\s*2,\s*binding\s*=\s*0,\s*std430\)",
                  "layout(binding = 0, std430)", text)
    # push constants -> a normal UBO
    text = re.sub(r"layout\(push_constant,\s*std430\)\s*uniform",
                  f"layout(std140, binding = {PUSH_UBO_BINDING}) uniform", text)

    bindings: dict[tuple[bool, str, int, int | None], int] = {}
    declarations: list[str] = []

    def bind(stype: str, own: bool, t_off: int | None, s_off: int | None) -> str:
        if t_off is None:
            raise Unsupported("texture/sampler not read from the constants")
        key = (own, stype, t_off, s_off)
        if key not in bindings:
            bindings[key] = len(bindings)
            declarations.append(
                f"layout(binding = {bindings[key]}) uniform {stype} dk_tex_b{bindings[key]};")
        return f"dk_tex_b{bindings[key]}"

    def find_heap(inner: str, name: str, start: int = 0) -> tuple[str | None, int]:
        at = inner.find(name, start)
        if at < 0:
            return None, start
        ob = inner.find("[", at + len(name))
        if ob < 0:
            return None, start
        cb = matching(inner, ob, "[", "]")
        return inner[ob + 1:cb], cb + 1

    if has_textures and has_samplers:
        pos = 0
        out = []
        while True:
            m = re.search(r"(sampler2D|sampler3D|samplerCube)\(", text[pos:])
            if not m:
                out.append(text[pos:])
                break
            start = pos + m.start()
            stype = m.group(1)
            open_i = start + len(stype)
            close_i = matching(text, open_i, "(", ")")
            inner = text[open_i + 1:close_i]
            texpr, after = find_heap(inner, TEXTURE_HEAPS[stype][0])
            sexpr, _ = find_heap(inner, "g_SamplerDescriptorHeap", after)
            if texpr is None or sexpr is None:
                out.append(text[pos:close_i + 1])
                pos = close_i + 1
                continue
            t_src = word_source(texpr, temps, own_temps)
            s_src = word_source(sexpr, temps, own_temps)
            out.append(text[pos:start])
            if t_src and s_src and t_src[0] == s_src[0]:
                # Shared constants (the game's tables) or the renderer's own
                # constants (present / FSR): both are bound samplers, read by
                # the back end from the matching constant block.
                out.append(bind(stype, t_src[0] == "own", t_src[1], s_src[1]))
            else:
                out.append(bind(stype, False,
                                t_src[1] if t_src and t_src[0] == "shared" else None,
                                s_src[1] if s_src and s_src[0] == "shared" else None))
            pos = close_i + 1
        text = "".join(out)

    if has_textures:
        # A texture used alone (texelFetch, textureSize) needs no sampler.
        pos = 0
        out = []
        while True:
            m = re.search(r"(g_Texture2DDescriptorHeap|g_Texture3DDescriptorHeap|g_TextureCubeDescriptorHeap)\s*\[", text[pos:])
            if not m:
                out.append(text[pos:])
                break
            start = pos + m.start()
            stype = TEXTURE_HEAP_OF[m.group(1)]
            ob = text.find("[", start)
            cb = matching(text, ob, "[", "]")
            inner = text[ob + 1:cb]
            src = word_source(inner, temps, own_temps)
            out.append(text[pos:start])
            if src:
                out.append(bind(stype, src[0] == "own", src[1], None))
            else:
                out.append(bind(stype, False, None, None))
            pos = cb + 1
        text = "".join(out)

    # Drop the extensions that only exist for Vulkan constructs (the tables,
    # texture-only functions, scalar layout).
    for ext in DROPPED_EXTENSIONS:
        text = re.sub(rf"^#extension {re.escape(ext)}.*\n", "", text, flags=re.M)
    text = re.sub(r"\bnonuniformEXT\(([^()]*)\)", r"(\1)", text)

    # Mesa's GLSL (uam) spells the Vulkan built-ins gl_VertexIndex /
    # gl_InstanceIndex as gl_VertexID / gl_InstanceID.
    text = re.sub(r"\bgl_VertexIndex\b", "gl_VertexID", text)
    text = re.sub(r"\bgl_InstanceIndex\b", "gl_InstanceID", text)

    # Vertex inputs: renumber to 0..N and remember the original locations for
    # the pipeline's input layout.
    vin: list[int] = []
    if stage == "vert":
        inputs = list(INPUT_DECL.finditer(text))
        if inputs:
            vin = [int(m.group(1)) for m in inputs]
            for new, m in enumerate(inputs):
                text = text.replace(m.group(0), f"layout(location = {new}) in {m.group(2)};", 1)

    ubo_mask = 0
    for m in UNIFORM_DECL.finditer(text):
        b = re.search(r"binding\s*=\s*(\d+)", m.group(1))
        if b:
            ubo_mask |= 1 << int(b.group(1))
    ssbo_mask = 0
    for m in BUFFER_DECL.finditer(text):
        b = re.search(r"binding\s*=\s*(\d+)", m.group(1))
        if b:
            ssbo_mask |= 1 << int(b.group(1))

    meta = f"// banjo-dk ubo=0x{ubo_mask:x} ssbo=0x{ssbo_mask:x} tex={1 if has_textures else 0}"
    if vin:
        meta += " vin=" + ",".join(str(v) for v in vin)
    shared_bindings, own_bindings = [], []
    for (is_own, _stype, t, s), k in sorted(bindings.items(), key=lambda kv: kv[1]):
        entry = f"{k}:{t}:{65535 if s is None else s}"
        (own_bindings if is_own else shared_bindings).append(entry)
    if shared_bindings:
        meta += " texb=" + ",".join(shared_bindings)
    if own_bindings:
        meta += " ownb=" + ",".join(own_bindings)

    lines = text.split("\n")
    insert = [meta] + declarations
    lines[1:1] = insert
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--stage", choices=("vert", "frag"), required=True)
    a = ap.parse_args()
    try:
        src = open(a.input, encoding="utf-8").read()
        out = convert(src, a.stage)
    except (OSError, Unsupported) as e:
        print(f"deko3d_glsl: {a.input}: {e}", file=sys.stderr)
        return 1
    with open(a.output, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
