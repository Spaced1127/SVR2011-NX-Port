# Third-party notices

SVR2011-NX is a fan-made Nintendo Switch homebrew port of *WWE SmackDown vs.
Raw 2011* (Xbox 360). It is built on the ReXGlue static-recompilation runtime
and the public work of the Xbox 360 recompilation community. No game material
is included in this repository.

## Projects this port is built on

| Project | Used for | Licence |
|---|---|---|
| [WWE SmackDown vs. Raw 2011 PC port](https://github.com/KaikoClanworth1/wwe-svr2011-pc) by KaikoClanworth1 and contributors | The game hooks, native renderer, tools and configuration this Switch port starts from | MIT (port's own code); third-party parts keep their own licences |
| [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk) by Tom Clay, with portions from [Xenia](https://xenia.jp) | Code generator, Xbox 360 kernel/runtime, GPU command processing, XMA audio, virtual filesystem | BSD-3-Clause (`sdk/LICENSE`) |
| Horizon (Switch) layer of the SDK by StevensND, from [NFSMW-NX](https://github.com/StevensND/nfsmw-nx) | Guest memory, exception handling, ARM64 fibers, threading, input, audio, presentation, clocks, NRO packaging | BSD-3-Clause (as part of the SDK) |
| [plume](https://github.com/renderbag/plume) by renderbag and contributors, with the Switch/deko3d work from [SA2-NX](https://github.com/ChanseyIsTheBest/sa2-nx) | The native renderer's graphics interface | MIT (`third_party/plume/LICENSE`) |
| [Mesa](https://mesa3d.org) / [mesa-switch](https://github.com/danfromtico/mesa-switch) by danfromtico | NVK (Vulkan) and NAK (shader compiler) for the Tegra X1 | MIT (Mesa's per-file licences) |
| [deko3d](https://github.com/devkitPro/deko3d) by fincs / devkitPro | Optional low-level Switch graphics backend | zlib |
| [uam](https://github.com/devkitPro/uam) by fincs, with SwitchWakerHD's patches | Optional deko3d shader compiler | zlib (uam), MIT (Mesa files), MPL-2.0 (SwitchWakerHD's patches) |
| [XenosRecomp](https://github.com/hedge-dev/XenosRecomp) by hedge-dev and contributors | Xbox 360 shader microcode to HLSL translator | MIT |
| [FFmpeg](https://ffmpeg.org) | XMA/WMA audio decoding and the Bink reader/writer | LGPL-2.1-or-later (configured without GPL parts) |
| [libmspack](https://www.cabextract.org.uk/libmspack/) | LZX decompression | LGPL-2.1 |
| [libnx](https://github.com/switchbrew/libnx) and the devkitA64 runtime | Nintendo Switch homebrew system interface | ISC; newlib and GCC runtime licences |
| [Dear ImGui](https://github.com/ocornut/imgui) | Runtime overlays and settings UI | MIT |
| [fmt](https://github.com/fmtlib/fmt), [spdlog](https://github.com/gabime/spdlog) | Formatting and logging | MIT |
| [xxHash](https://github.com/Cyan4973/xxHash) | Hashing | BSD-2-Clause |
| [SIMDe](https://github.com/simd-everywhere/simde) | Portable SIMD helpers | MIT |
| [toml++](https://github.com/marzer/tomlplusplus) | Configuration parsing | MIT |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers), [SPIRV-Headers](https://github.com/KhronosGroup/SPIRV-Headers), [SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools) | Vulkan and SPIR-V headers/tools | MIT / Apache-2.0 |
| [Vulkan Memory Allocator](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) | Vulkan memory allocation | MIT |
| [glslang](https://github.com/KhronosGroup/glslang) | Shader compilation | BSD-3-Clause and others |
| [Zstandard](https://github.com/facebook/zstd), [zlib](https://zlib.net), [Expat](https://libexpat.github.io) | Compression / XML for NVK | BSD-3-Clause / zlib / MIT |

The `sdk/thirdparty` tree is fetched locally by `tools/fetch_thirdparty.py`
from ReXGlue SDK v0.10.0 and its submodules. It is not committed to this
repository; each fetched project keeps its own licence.

## No game material

This repository does not contain, and releases must not contain:

- the Xbox 360 disc image, `default.xex`, or any extracted game file;
- recompiled game code generated from `default.xex`;
- shader packs, texture packs, audio, video, fonts, icons or other assets
  derived from the game;
- the original game's executable, libraries or data in any form.

The NRO is built locally from the user's own legally obtained copy of the
game. The user is responsible for complying with the game's licence and with
the laws of their country.

## Trademarks

*WWE SmackDown vs. Raw 2011* and all related names and logos are trademarks
of their respective owners. Nintendo Switch is a trademark of Nintendo. Xbox
360 is a trademark of Microsoft. This project is not affiliated with or
endorsed by WWE, THQ, Yuke's, Microsoft, Nintendo or any of their affiliates.
