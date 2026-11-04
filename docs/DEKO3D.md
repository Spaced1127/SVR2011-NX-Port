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
