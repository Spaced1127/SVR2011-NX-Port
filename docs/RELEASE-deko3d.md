# WWE SmackDown vs. Raw 2011 — Nintendo Switch deko3d port (source builder)

**Source-only.** No game data, recompiled game code, shader packs, textures,
screenshots or prebuilt NROs are included. You must own the Xbox 360 game
(`default.xex`) and build the NRO locally.

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
| deko3d | stock 1020 / 307.2 / 1331.2 MHz | **33 fps** | 6.3 ms | 30.2 ms |
| deko3d, `frame_rate=30` | 1963.5 / 998.4 / 1866 MHz | 30 fps | 7.7 ms | 33.3 ms |

- The menus run at 60 fps; heavy entrances (878–924 draws) drop to 15–21 fps.
- `frame_rate=30` is worse than 60: the game's 30 Hz world step does twice the
  work per frame. Use 60.
- FSR 1 (`native_upscale="fsr1"`, quality 4) is active at a 288p scene but
  does not change the CPU-limited fps.
- `-O3` for the generated code did not move the numbers; PGO instrumentation
  crashes at startup on the Switch and is not shipped.
- The main thread is the limit (97% of one A57 core); the phone's 60 fps in the
  Android build is its 3+ GHz big core and faster GPU.

## Known issues

- The app's Vulkan/ImGui overlays (settings, FPS overlay, achievements) are
  not drawn on the deko3d path; the game's own UI is rendered by deko3d.
- The folder save `Saves/SaveData.dat/SaveData.Dat` loads; creating a new flat
  save is slow/unreliable on the console.
- `dlc_fan_axxess=true` hangs in the fake DLC loader; keep it `false`.
- The stock console is CPU-limited around 33 fps at 60 logic; 60 fps is not
  reachable on the Switch at stock clocks.

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
