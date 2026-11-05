# deko3d backend (exploration branch)

This branch is the deko3d performance port. `main` keeps the working NVK/Vulkan
build; this branch is where the Switch-native renderer is built.

## Why

The NVK build boots and plays, but the in-ring scene is draw-bound:

```text
render passes per frame 7.0
draws 663 (drawn 592)
draw 8.6 ms, submit 26 ms, span 49.8 ms
fps 20.0
CPU 1785 MHz, GPU 921.6 MHz (overclocked)
```

Changing `native_render_scale`, effects or shadows does not move the frame
time. The cost is NVK's per-draw command path (about 660 draws, ~26 ms just to
submit) plus the GPU present. deko3d, the Switch's own GPU API, removes the
Vulkan/NVK layer and should cut that cost enough for 30 fps at 720p.

## What deko3d is, and what it is not

deko3d is **not** a drop-in `gpu_backend` switch. It needs:

1. plume's deko3d backend (`plume_deko3d*.{h,cpp}`, MIT, from banjo-nx /
   sa2-nx) and the devkitPro `deko3d` + `uam` libraries.
2. A deko3d Switch window/presenter path in the SDK. The current window,
   presenter and UI are Vulkan/NVK. `sa2-nx` calls this the "no-NVK switch".
3. A `backend_deko3d.cpp` for our native renderer (`port/src/native/gpu.h`).
   The renderer already draws through plume's `RenderDevice` /
   `RenderCommandList`; the backend owns device creation, frame publish and
   the pipeline cache.
4. A shader pipeline. Our shaders are Vulkan SPIR-V with storage buffers and
   bindless tables. deko3d needs GLSL compiled by uam to DKSH:
   `SPIRV-Cross -> GLSL -> uam -> DKSH`, plus a binding model that deko3d can
   express. This is the largest risk.

The Renut renderer used by sa2-nx 1.0.3 is GPL-3.0. **Do not copy it.** This
project stays MIT/BSD. We keep our own native renderer and write the deko3d
backend for it. plume's deko3d backend is MIT; uam is zlib/MIT/MPL-2.0.

## Current architecture (main)

- `port/src/native/gpu.h`: the backend interface (`Backend`,
  `CreateVulkanBackend`, `PublishFrame`, `ShaderFormat`, pipeline cache).
- `port/src/native/backend_vulkan.cpp`: Vulkan device, external-frame
  handoff, NVK format report, pipeline cache.
- `port/src/native/native_renderer.cpp`: the renderer. It uses plume's
  abstract API; the Vulkan-specific parts are in the backend.
- `port/src/native/textures.cpp`: texture upload/untile/cache.
- `port/src/native/shaders/`: shader templates; the generated shader pack is
  `native_shaders/shaders.spv.pak` (not committed).
- `sdk/src/ui/window_switch.cpp`, `sdk/src/ui/vulkan/vulkan_presenter.cpp`:
  the Switch window and presentation.

## Progress (this branch)

- **plume deko3d back end imported** (`plume_deko3d.{h,cpp}`,
  `plume_deko3d_commands.cpp`, MIT) and `uam` (`third_party/uam`,
  zlib/MIT/MPL-2.0) added. `PLUME_DEKO3D=ON` builds them for the Switch.
- **`backend_deko3d.cpp`** added: plume deko3d device, presentation queue and
  a default-NWindow swapchain; the finished frame is copied and presented.
  `native_backend = "deko3d"` selects it, and on the Switch it is the default.
- **Shader conversion works on every game shader**: `spirv-cross` Vulkan
  GLSL -> `tools/deko3d_glsl.py` produces the `// banjo-dk` layout with
  per-draw `dk_tex_bK` textures (2D, 3D and cube) and `texb=` shared-constant
  offsets. The renderer's own shaders (present, FSR 1, debug) use the same
  bound-sampler path with `ownb=` own-constant offsets, so every shader is
  compiled by uam the same way. `tools/deko3d_shaders.py` turns
  `shaders.spv.pak` into `shaders.dk.pak` (BDK3 blobs for uam): 926 shaders
  converted, 0 skipped. The converter also rewrites Vulkan's
  `gl_VertexIndex` / `gl_InstanceIndex` to Mesa's `gl_VertexID` /
  `gl_InstanceID`, which uam's GLSL frontend expects.
- **Non-compact tables**: deko3d uses the renderer's big texture/sampler
  tables (set 0/1) as one image descriptor set and one sampler set. The
  renderer writes global texture indices for deko3d (the 2D, 3D and cube
  ranges are contiguous in deko3d), and `bindTextures` reads the per-draw
  texture/sampler words from the upload ring using the shared-constants
  offset in the push constants.
- **Presentation**: with `native_backend=deko3d`, `svr2011_app` sets
  `switch_vulkan_surface=false`, so the SDK's Vulkan presenter never opens a
  swapchain on the default NWindow; the deko3d backend owns it and presents
  the frame image 1:1 (RGBA8, 720p handheld / the display resolution docked).
  The app's Vulkan/ImGui overlays are not drawn on this path yet.
- **Performance**: measured on hardware, in-ring, 60 Hz game logic:

  | Build | CPU / GPU / RAM | In-ring | draw | span |
  |---|---|---|---|---|
  | NVK (main) | 1785 / 921.6 / 1866 MHz | ~20 fps | 8.6 ms | 49.8 ms |
  | deko3d | 1963.5 / 998.4 / 1866 MHz | **35 fps** | 6.0 ms | 29.0 ms |
  | deko3d, recorder off (`replays=false`) | 1963.5 / 998.4 / 2133 MHz | **~51 fps** | 3.7 ms | 19.4 ms |
  | deko3d | stock 1020 / 307.2 / 1331.2 MHz | **33 fps** | 6.3 ms | 30.2 ms |
  | deko3d, `frame_rate=30` | 1963.5 / 998.4 / 1866 MHz | 30 fps | 7.7 ms | 33.3 ms |

  The menus run at 60 fps; heavy entrances (878–924 draws) drop to 15–21 fps.
  With `replays=false` the recorder's per-update work is skipped: the `107`
  log measures 50.8–55.4 fps in-ring over five-second windows at draw 3.7 ms
  and span 19.4 ms (the `104` log, before the present copy list was reused,
  measured 41.3–46.6 fps). `frame_rate=30` is worse than 60 because the game's
  30 Hz world step does twice the work per frame. The measured profile is
  **no FSR**:
  `native_upscale="off"`, `native_render_scale=0.5`,
  `native_scale_effects=true`, `native_record_thread=true`, 720p, 60 Hz
  (`docs/performance-svr2011.toml`). FSR 1 quality 4/5 is active in the
  shader path but measured **~25 fps** — the EASU/RCAS passes cost more on the
  Switch GPU than the smaller scene saves. `-O3` for the generated code did
  not move the numbers; PGO instrumentation crashes at startup on the Switch
  and is not shipped.
- **Shader/present fixes**: `gl_VertexIndex`/`gl_InstanceIndex` are rewritten
  to Mesa's `gl_VertexID`/`gl_InstanceID`; present and FSR use bound samplers
  from the own-constants block (`ownb`) instead of bindless handles. Without
  these, uam failed the present vertex shader and the renderer fell back to an
  unscaled 50% scene resolve (the top-left quadrant).
- **Clean baseline**: tag `deko3d-perf-baseline` (`abe2a66`); the last
  measured 35 fps build was rebuilt from scratch (host codegen + generated
  game code + NRO) and the shader pack regenerated (926 converted, 0 skipped).
- **Replay crash**: with `replays=true`, the recorder's queued callbacks read
  guest `0xDC` at the match start; `replays=false` now drops both recorder
  callback pairs in `frame_rate.cpp` (and the match-end highlights are off).
  The measured profile keeps it off.
- **Match start**: the `103` log's remaining failure was the replay recorder's
  own update (`sub_8217BC90`) still queueing jobs (pass 20 stuck for 10 s) and
  the first in-ring frame closing. With `replays=false` the diagnostic build
  (`0FD75327…`) skips that update; the `104` run reaches the ring, and the `107`
  run (with the present fix) holds 50.8–55.4 fps. The 51 KB
  `00181780173CF87B.vs.s1` whose GLSL tail ended the `103` log compiles on
  desktop and on aarch64 (qemu) uam with a 1 MB stack and 28–49 MB RSS, so it
  was not the fault. The 16 MB uam stack and the variant trace stay in the
  build until the next clean cut.
- **Screen-capture freeze**: taking a Capture screenshot in-ring froze the
  console (`104`: logging stops at 05:11:51, the perfil dump shows every thread
  at 0% CPU, no crash report). The present path created a command list per
  frame; its destructor calls `dkQueueWaitIdle`, which waits for the present as
  well, so when the capture held the window's buffers the render thread
  blocked silently and the logic thread waited behind it. The backend now
  reuses one command list and fence (waiting only for the copy fence, which
  signs before the present), uses three swapchain images, and pauses
  presenting while the applet has no focus (`91C5717B…`).
- **Match end with replays off**: the `107` match ended at the pinfall but
  stayed in the end's step 0: the recorder update is skipped, so its update
  side (`+1504`) never leaves 1 for the 4/6 the 8 s fallback handled. The
  fallback now forces side 1 to 5 as it did for the Android/Steam Deck states;
  the celebration and results screen follow without the replay
  (`13322768…`).
- **Replay recorder (off in the supported profile)**: with `replays=true` the
  first recording callback freed the clip buffer the attract demo left behind;
  one clip's destructor read guest `0xDC`. `replays.cpp` zeroes the 140 clip
  pointers at the match start for a test, but replays are not part of the
  measured/supported profile: the recorder costs CPU and its highlighting is
  unfinished. The supported profile keeps `replays=false` and still reaches the
  celebration and results.
- **Arena crowd (off in the measured profile)**: the Switch's
  `std::filesystem::copy_file` returns `ENOSYS`, so the crowd-less arena
  copies depend on the stock files. The measured profile keeps
  `arena_crowd="off"` for the GPU cost; crowd rendering is not part of the
  supported profile.
- **Still open**: the app's Vulkan/ImGui overlays are off on the deko3d path;
  a persistent DKSH cache; a Clang cross-build of the generated code (the
  remaining codegen experiment).

## Building and testing this branch

```bash
# PC tools (once): SPIRV-Cross
git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Cross
cmake -S SPIRV-Cross -B SPIRV-Cross/build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C SPIRV-Cross/build spirv-cross

# shader pack (writes shaders.dk.pak beside shaders.spv.pak)
SPIRV_CROSS=/path/to/spirv-cross python3 tools/deko3d_shaders.py \
    /path/to/native_shaders /path/to/native_shaders/deko3d

# Switch NRO (devkitPro, libnx deko3d, NVK SDK for the emulated GPU)
DEVKITPRO=/opt/devkitpro PORTLIBS_PREFIX=/opt/devkitpro/portlibs/switch \
REXGLUE_SWITCH_NVK_SDK=/path/to/nvk/extracted \
bash tools/build_switch.sh --switch
```

Copy `svr2011.nro` to the SD root and the shader pack to
`Game_files/native_shaders/shaders.dk.pak` (the layout is in
[`../README.md`](../README.md)). The deko3d path is selected by
`native_backend = "deko3d"` (the default on the Switch); `native_backend =
"auto"` keeps the emulator's Vulkan backend for comparison.

## Working performance profile

The measured profile is
[`performance-svr2011.toml`](performance-svr2011.toml): no FSR,
`native_render_scale=0.5`, `native_scale_effects=true`,
`native_record_thread=true`, 720p, 60 Hz, `replays=false`. The `107` log
measures 50.8–55.4 fps in-ring (draw 3.7 ms, span 19.4 ms). FSR 1 quality 4/5
was ~25 fps in the full-screen present build; the EASU/RCAS passes cost more
than the smaller scene saves. Add `dbg_boot="match"`, `dbg_match="..."` and
`dbg_entrances=false` for a straight-to-match test; the normal profile boots
through the menus.

Screenshots of the running deko3d build live in
[`screenshots/`](screenshots/) (documentation only).

## PGO for the recompiled game code

The generated game code is most of the CPU time. `-O3` alone did not move it;
profile-guided optimization is the next step. **Measured: the instrumented NRO
crashes at startup on the Switch (libgcov/Horizon), so PGO is not shipped.**
The flow below is kept for a future attempt. The same build tree must be used
for both passes.

1. Instrumented NRO. The profile directory is a console path (`sdmc:`):

```bash
SVR2011_PGO=generate SVR2011_PGO_DIR="sdmc:/switch/SVR2011/pgo" \
  bash tools/build_switch.sh --switch
```

Copy that NRO to the SD, boot it, play a representative match (menus,
entrance, in-ring, attacks), and close the app cleanly so libgcov writes the
`.gcda` files to `sdmc:/switch/SVR2011/pgo`.

2. Copy the `pgo` folder from the SD to the host, then rebuild with the same
build tree and the host path:

```bash
SVR2011_PGO=use SVR2011_PGO_DIR="/mnt/h/Projects/svr2011-sd2/pgo" \
  bash tools/build_switch.sh --switch
```

The second NRO is the optimized one. Keep the instrumented NRO for another
profile run if the first is not representative.

## Milestones

### 0. Baseline and build

- Keep `main` as the reference: NVK, 20 fps, logs in `docs/TESTING.md`.
- Add deko3d/uam to the devkitPro build (`-ldeko3d`, `-luam`), but keep the
  NVK path building until the deko3d path is proven.

### 1. plume deko3d backend

- Bring in `plume_deko3d*.{h,cpp}` from banjo-nx/sa2-nx (MIT) and the few
  plume changes they carry (`patches/plume-*.patch`).
- Build a standalone test: clear a deko3d swapchain to a colour and present
  it on hardware. No game, no shaders.
- Acceptance: a visible frame at 60 Hz on the Switch, no NVK linked.

### 2. SDK window/presenter

- Port the Switch window/presenter from the Vulkan swapchain to a deko3d
  swapchain (the sa2-nx SDK patch is the reference).
- Keep the UI path working (ImGui through plume/deko3d).
- Acceptance: the app's own UI (FPS overlay, settings pages) draws and
  presents through deko3d; NVK is no longer linked.

### 3. `backend_deko3d.cpp`

- Implement `Backend` with a plume deko3d device: `CreateInterface`,
  `ShaderFormat`/`ShaderExtension`, `PublishFrame`, `GetFrame`,
  `PipelineCreated`, `Load/SavePipelineCache`, `VideoMemory` (best effort).
- Use the **compact tables** path (`native_compact_tables = true`) first:
  per-draw texture sets and uniform-buffer constants, which map to deko3d
  more directly than descriptor indexing/storage buffers.
- Acceptance: the menus and the practice ring draw through deko3d with the
  existing renderer, even if some effects are missing.

### 4. Shader pipeline

- Add a converter: `spirv-cross` (Apache-2.0) from the generated SPIR-V to
  GLSL, then uam to DKSH on the console; cache the DKSH variants in
  `native_shaders/deko3d_shaders.bin` (not committed).
- Start with `present`, then the 2D/menu shaders, then one scene shader.
- Resolve the binding model: deko3d uniform buffers, textures/samplers,
  vertex/index buffers, render targets and resolves. The compact path's
  shader templates are the starting point.
- Acceptance: a full 1v1 match with correct colours, textures and resolve
  targets.

### 5. Performance and parity

- Measure the render thread and game thread separately (the sa2-nx guide's
  method).
- Target: 30 fps at 720p handheld on the overclocked console (CPU 1785 /
  GPU 921.6), then stock clocks.
- Re-enable effects/shadows if the budget allows.
- Keep a per-draw signature/guard path for any game-specific draw workaround.

## Risks

| Risk | Why | Mitigation |
|---|---|---|
| Shader binding model | Our SPIR-V uses storage buffers/bindless tables; deko3d/uam want GLSL/DKSH | compact tables first; rewrite the shader templates around uniform buffers and per-draw sets |
| Render targets/resolves | The renderer models EDRAM surfaces and resolves | map to deko3d images + `dkImage` resolves; validate with the menu and one scene |
| Frame handoff | UI and renderer must share one swapchain | do the SDK present path first (milestone 2) |
| Memory | deko3d memory pools and the guest's 512 MB | reuse the NVK allocator lessons; keep textures in blocks |
| FSR2/DLSS | Vulkan-specific | leave off; FSR1/off first |
| GPL contamination | Renut is GPL-3.0 | do not copy it; keep the MIT/BSD renderer |

## References

- `ChanseyIsTheBest/sa2-nx`: `docs/deko3d-renderer-guide.md`,
  `docs/porting-guide.md`, `app/thirdparty/plume` (deko3d backend), `uam`.
- `StevensND/nfsmw-nx`: the NVK Switch layer this port started from.
- banjo-nx: the plume deko3d backend and the shader passes.
- devkitPro: `deko3d` (zlib), `uam` (zlib/MIT/MPL-2.0).

## Branch rules

- `main` stays the working NVK build.
- This branch may break; keep the deko3d path behind a build option until it
  boots on hardware.
- No game data, generated game code, shader packs or NROs in the branch.
  `python3 tools/check_no_game_data.py` must pass before every push.
