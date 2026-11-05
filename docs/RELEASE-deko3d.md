# WWE SmackDown vs. Raw 2011 — Nintendo Switch deko3d port (source builder)

**Source-only.** No game data, recompiled game code, shader packs, textures or
prebuilt NROs are included. You must own the Xbox 360 game (`default.xex`) and
build the NRO locally. Maintainer screenshots of the running port live in
[`docs/screenshots/`](screenshots/) as documentation only; they are not game
data used by the build.

This is the `deko3d` branch: the native renderer draws and presents on the
Switch's own GPU API instead of Vulkan/NVK. `main` keeps the working NVK
build for comparison.

## Requirements

- devkitPro with devkitA64, libnx and deko3d (`/opt/devkitpro`).
- The NVK SDK for the emulated Xenos GPU (`REXGLUE_SWITCH_NVK_SDK`).
- SPIRV-Cross on the PC (shader conversion).
- Your own extracted Xbox 360 game folder (`default.xex`, `pac/`, `sound/`,
  `movies/`, ...). No game files are in this repository.

## Build

```bash
# 1. PC tool: SPIRV-Cross
git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Cross
cmake -S SPIRV-Cross -B SPIRV-Cross/build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C SPIRV-Cross/build spirv-cross

# 2. deko3d shader pack, from the SPIR-V pack the renderer's converter writes
SPIRV_CROSS=/path/to/spirv-cross python3 tools/deko3d_shaders.py \
    /path/to/native_shaders /path/to/native_shaders/deko3d
# copy the resulting deko3d/shaders.dk.pak beside shaders.spv.pak

# 3. Switch NRO
DEVKITPRO=/opt/devkitpro PORTLIBS_PREFIX=/opt/devkitpro/portlibs/switch \
REXGLUE_SWITCH_NVK_SDK=/path/to/nvk/extracted \
bash tools/build_switch.sh --switch
```

Copy `svr2011.nro` and `native_shaders/` (with `shaders.dk.pak`) to the SD
card. `native_backend = "deko3d"` is the default on the Switch; the Vulkan
presenter is disabled so deko3d owns the NWindow.

## Performance (measured on hardware)

In-ring, 60 Hz game logic:

| Build | CPU / GPU / RAM | In-ring | draw | span |
|---|---|---|---|---|
| NVK (main) | 1785 / 921.6 / 1866 MHz | ~20 fps | 8.6 ms | 49.8 ms |
| deko3d | 1963.5 / 998.4 / 1866 MHz | **35 fps** | 6.0 ms | 29.0 ms |
| deko3d, recorder off (`replays=false`) | 1963.5 / 998.4 / 2133 MHz | **~51 fps** | 3.7 ms | 19.4 ms |
| deko3d | stock 1020 / 307.2 / 1331.2 MHz | **33 fps** | 6.3 ms | 30.2 ms |
| deko3d, `frame_rate=30` | 1963.5 / 998.4 / 1866 MHz | 30 fps | 7.7 ms | 33.3 ms |

- The menus run at 60 fps; heavy entrances (878–924 draws) drop to 15–21 fps.
- The recorder-off row is the same profile with `replays=false`, which also
  skips the replay recorder's per-update work (`sub_8217BC90`). The `107` log
  measures 50.8–55.4 fps over five-second windows with draw 3.7 ms and span
  19.4 ms; the `104` log, before the present copy list was reused, measured
  41.3–46.6 fps.
- `frame_rate=30` is worse than 60: the game's 30 Hz world step does twice the
  work per frame. Use 60.
- FSR 1 (`native_upscale="fsr1"`, quality 4/5) is **slower** in the
  full-screen present build: ~25 fps vs ~35 fps without it. The EASU/RCAS
  passes cost more on the Switch GPU than the smaller scene saves. The
  measured 35 fps profile is `native_upscale="off"`, `native_render_scale=0.5`,
  `native_scale_effects=true`, `native_record_thread=true`, 720p, 60 Hz — kept
  in [performance-svr2011.toml](performance-svr2011.toml).
- The `gl_VertexIndex` -> `gl_VertexID` shader rewrite and the `ownb` bound
  sampler path fixed the present pipeline; before that, the renderer fell back
  to an unscaled scene resolve (the top-left quadrant) and the FSR passes were
  not reached.
- `-O3` for the generated code did not move the numbers; PGO instrumentation
  crashes at startup on the Switch and is not shipped.
- The main thread is the limit (97% of one A57 core); the phone's 60 fps in the
  Android build is its 3+ GHz big core and faster GPU.

## Reproducible baseline

- Source commit: `abe2a66` (`deko3d-perf-baseline`).
- Clean build from scratch: `out/host`, `out/switch` and `out/switch-deko3d`
  removed, then `bash tools/build_switch.sh --switch`; 746/746 host codegen +
  1054/1054 Switch objects; `-O3` is applied to `svr2011_recomp` after the
  SDK's `-O2`.
- Shader pack rebuilt with `tools/deko3d_shaders.py` + `spirv-cross`:
  926 shaders converted, 0 skipped, 1,511 files.
- Working settings: [`performance-svr2011.toml`](performance-svr2011.toml).
- Local build fingerprint (varies with your generated code): `svr2011.nro`
  82,770,117 bytes, SHA-256
  `A16E982777981679E5C242D552B42E4A68D714CEFE10CFB4D3412806C3F52ADB`;
  `shaders.dk.pak` 14,387,537 bytes, SHA-256
  `3A15F39B263BA45B23E3682C48252C8F1B6BE61EF330A158342F1EC5AE9D94E5`.
- Replay-fix build (commit `1917a44`: `frame_rate` drops the recorder callbacks
  with `replays=false`; the arena copy fallback is reverted):
  `svr2011.nro` 82,770,117 bytes, SHA-256
  `23B815BB6EF4CF91FEF2DFADA39C90F570197245F74D2D27FFD7CAE65EF21052`;
  the shader pack is unchanged.
- Match-start diagnostic build: `svr2011.nro` 82,770,117 bytes,
  SHA-256 `0FD753271B7256A6E02FE42B5E8C7393B630F0524273A1F92BB1FF8B14387EB4`;
  the shader pack is unchanged. It skips the recorder update
  (`sub_8217BC90`) with `replays=false`, logs every run-time shader variant,
  writes the last large variant to `sdmc:/svr2011_last_shader.glsl` and
  `sdmc:/svr2011_last_shader.txt` before compiling it, gives the uam thread
  16 MB of stack, and logs up to 96 deko3d memory blocks. The `104` run with
  this build reaches the in-ring scene.
- Screen-capture fix build: `svr2011.nro` 82,770,117 bytes, SHA-256
  `91C5717B963A241ADA932B246F48368F5DA2DE597DA92D965D83854856E3DBD7`;
  the shader pack is unchanged. The present path reuses one command list and
  fence instead of creating a list per frame (its destructor's
  `dkQueueWaitIdle` froze the render thread when the Capture button held the
  display), uses three swapchain images, and pauses presenting while the
  applet has no focus.
- Match-end fix build (current): `svr2011.nro` 82,770,117 bytes, SHA-256
  `13322768BB9EA32EA9D76E2AE11F270D44FD63F8921F1901F24AC607FC1F35B5`;
  the shader pack is unchanged. With `replays=false` the recorder update is
  skipped, so the match end's step 0 waited forever on its update side
  (`+1504 1`). The 8 s fallback, which already forced the Android/Steam Deck
  states 4/6 done, now forces side 1 too: the celebration and results screen
  follow without the replay.

## Screenshots

Game screenshots of the deko3d build on Switch hardware (handheld, 1280x720;
the top overlay shows the overclocked clocks):

- [Title screen](screenshots/01-title-screen.jpg)
- [KANE VS. HURRICANE match select](screenshots/02-match-select.jpg)

They are documentation only, not build inputs or game data; the release guard
allows images only under `docs/screenshots/`.

## Known issues

- Instant replays / the replay recorder (`replays=true`) crash the guest at
  the match start (a read of guest `0xDC` on the replay thread). The
  `frame_rate` hook now drops the recorder's queued callbacks when
  `replays=false`, and the match-end highlights are off; the measured profile
  keeps it off. This is a port replay-recorder issue, not a deko3d rendering
  issue.
- The app's Vulkan/ImGui overlays (settings, FPS overlay, achievements) are
  not drawn on the deko3d path; the game's own UI is rendered by deko3d.
- The folder save `Saves/SaveData.dat/SaveData.Dat` loads; creating a new flat
  save is slow/unreliable on the console.
- `dlc_fan_axxess=true` hangs in the fake DLC loader; keep it `false`.
- The stock console is CPU-limited around 33 fps at 60 logic; 60 fps is not
  reachable on the Switch at stock clocks.
- The Switch's `std::filesystem::copy_file` ends in `ENOSYS` ("Function not
  implemented"); the arena overlay's fallback copies are therefore skipped, so
  `arena_crowd=off` does **not** replace the stock arena files on the Switch
  (the crowd may still render). A stream-copy fallback was tried but blocked
  startup at a black screen while copying the arena packs, so it is reverted.

## Licenses

- The port: MIT (see `LICENSE`).
- The SDK layer: BSD-3-Clause.
- plume and its deko3d back end: MIT.
- uam: zlib/MIT/MPL-2.0 (see `third_party/uam/LICENSE`).
- deko3d: zlib (devkitPro).
- SPIRV-Cross: Apache-2.0 (PC build tool only).
- AMD FidelityFX FSR 1 shaders: MIT (third-party notices in the repository).

No game assets are distributed. WWE SmackDown vs. Raw 2011 is a trademark of
its owners; this project is not affiliated with them.
