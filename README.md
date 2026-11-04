# SVR2011-NX

**WWE SmackDown vs. Raw 2011 — Nintendo Switch homebrew port.**

This is a native Nintendo Switch homebrew port of the Xbox 360 version of
*WWE SmackDown vs. Raw 2011*. It is not an emulator: the game's PowerPC code
is statically recompiled to C++ with
[ReXGlue](https://github.com/rexglue/rexglue-sdk), built with
devkitA64/libnx, and rendered by the port's native renderer.

The port is based on the public
[WWE SmackDown vs. Raw 2011 PC port](https://github.com/KaikoClanworth1/wwe-svr2011-pc)
by KaikoClanworth1 and contributors, and on the Horizon (Switch) layer of the
public NFSMW-NX and SA2-NX ReXGlue ports.

Two renderer branches exist:

| Branch | Renderer | In-ring (60 Hz logic) |
|---|---|---|
| `main` | Vulkan through Mesa NVK | ~20 fps (overclocked) |
| `deko3d` | the Switch's own deko3d API | **35 fps overclocked, 33 fps stock** |

The `deko3d` branch is the performance path; `main` keeps the NVK fallback.

> **Status: playable.** Boot, menus, save loading, 1v1 matches, movement,
> attacks, audio and entrances work. The `deko3d` branch fixes the NVK
> draw/submit bottleneck and reaches 33–35 fps in-ring; the menus run at
> 60 fps. Heavy entrances drop to 15–21 fps. Creating a save on the console is
> still slow/unreliable; a folder save made by the PC build loads correctly.

---

## No game material

This repository contains **no game data and no recompiled game code**.

You need your own legally obtained Xbox 360 copy of *WWE SmackDown vs. Raw
2011* (the disc image, or its extracted `default.xex` and game files). The NRO
is generated locally from that copy. The public release is a **builder, not a
playable NRO**: the NRO contains the recompiled game code generated from
`default.xex`, so distributing it would distribute the game's code even if
all assets were streamed from the user's folder.

Do not open issues or pull requests that attach an ISO, `default.xex`, game
files, shader packs, textures, audio, video, screenshots of the game, or a
prebuilt NRO. See [docs/LEGAL.md](docs/LEGAL.md).

---

## What works

| Area | State |
|---|---|
| Source import from the PC port (MIT) | Done |
| Horizon (Switch) ReXGlue SDK layer | Imported (BSD-3-Clause) |
| Host code generator (`rexglue`) from the user's `default.xex` | Done (403 generated files) |
| Switch portlibs + NVK + Vulkan build | Done |
| Switch NRO target | Builds (`svr2011.nro`, ~77–82 MB) |
| Mesa/NVK + Vulkan presentation | Works on hardware |
| deko3d native renderer | Works: full-screen 720p present, 33–35 fps in-ring |
| Boot to the main menu | Works |
| Match, audio, input | Works: 1v1 match loads and plays; attacks and movement work |
| Saves | A PC-made folder save loads (4.2 MB); creating a save on the console is still slow/unreliable |
| DLC | The fake Fan Axxess package hangs the DLC loader; keep `dlc_fan_axxess = false` |
| Folder-based Windows builder | Done (`Build SVR2011-NX.cmd`) |
| Source-only release packaging | Done (`tools/package_release.ps1`) |

---

## Requirements

- A Nintendo Switch 1 (Erista or Mariko) with Atmosphère/homebrew support.
  Switch 2 homebrew is a separate, less mature target and is not covered here.
- Your own Xbox 360 copy of the game and a way to read it (ISO or extracted
  files). About 5.4 GB of game data plus the ISO.
- A microSD card with enough free space (8 GB minimum; 16 GB recommended).
- A PC with:
  - WSL2 Ubuntu 24.04/26.04 or a Linux machine (the build scripts target
    Linux; Windows-native builds are possible but not documented here).
    Ubuntu 22.04 needs a newer Clang than its default for the C++23 host tool.
  - devkitPro with devkitA64, libnx and the Switch tools.
  - CMake 3.25+, Ninja, Git, Python 3.10+, Clang/GCC.
  - 32 GB RAM recommended for the LTO build of the recompiled game.
  - For Mesa/NVK: the Mesa build prerequisites (Meson, Ninja, Rust, bindgen,
    cbindgen, flex, bison, pkg-config).
- A title override (hold **R** while starting an installed game) or a
  forwarder with a **39-bit address space**. Album applet mode does not give
  the game enough memory.

---

## Quick start on Windows

Extract the release and run:

```text
Build SVR2011-NX.cmd
```

It asks for your extracted game folder, runs the WSL build, and leaves the NRO
and an SD-card folder in `%LOCALAPPDATA%\SVR2011-NX\dist`. It needs WSL2 with
Ubuntu and devkitPro; the script checks both and prints the install link if
devkitPro is missing. The first build takes 15–40 minutes.

The rest of this README is the manual WSL/Linux tutorial and the details
behind the builder.

---

## Building the NRO — manual tutorial

Commands are for WSL2 Ubuntu 24.04/26.04 or a Linux machine. All paths assume
the repository is at `~/svr2011-nx`; adjust them.

### 1. Install the host tools

```sh
sudo apt update
sudo apt install -y build-essential cmake ninja-build clang lld git python3 \
  pkg-config flex bison libssl-dev
```

Install devkitPro from <https://devkitpro.org/wiki/Getting_Started>. The
scripts assume `DEVKITPRO=/opt/devkitpro`; export it if yours is elsewhere.

### 2. Clone the repository and fetch the third-party sources

```sh
git clone https://github.com/Spaced1127/SVR2011-Switch-Port.git svr2011-nx
cd svr2011-nx
python3 tools/fetch_thirdparty.py
```

The repository tracks only the third-party files this port changed. The fetch
script clones ReXGlue SDK v0.10.0 and its submodules and fills `sdk/thirdparty`
(the fetched tree is ignored by git). It needs network access and a few
hundred MB of disk.

### 3. Build the Switch portlibs

NVK links against zlib, Expat and Zstandard. Build them for devkitA64:

```sh
sudo tools/build_portlibs.sh
```

They go into `$DEVKITPRO/portlibs/switch` by default. If you install them
elsewhere, export `PORTLIBS_PREFIX` and pass `-DCMAKE_PREFIX_PATH=<prefix>` to
the CMake configure.

### 4. Build Mesa/NVK for the Switch

The `main` branch renders through
[mesa-switch](https://github.com/danfromtico/mesa-switch), a Mesa port for
Horizon with NVK (Vulkan) and NAK (the shader compiler). Follow that project's
build instructions. The result contains:

```text
<mesa-sdk>/portlibs/switch/lib/libvulkan.a
<mesa-sdk>/portlibs/switch/include/vulkan/...
```

Export:

```sh
export REXGLUE_SWITCH_NVK_SDK=/path/to/mesa-sdk/portlibs/switch
```

This is the longest prerequisite. The current local build can also use a
prebuilt `nvk-switch` archive for the first link; a release build should use a
reproducible Mesa build.

### 5. Build the host code generator

```sh
tools/build_switch.sh --host
```

This configures `sdk/` in `out/host` and builds the `rexglue` code generator
with the host Clang. The tool runs on the PC; it is not part of the NRO.

### 6. Put your own game executable in place

```sh
cp /path/to/your/game/default.xex port/assets/default.xex
```

The file is ignored by git. Do not commit it. The code generator reads it to
produce `port/generated/default/` (also ignored).

### 7. Generate the recompiled game C++

```sh
tools/build_switch.sh --codegen
```

or, by hand:

```sh
cd port
../out/host/rexglue codegen svr2011_manifest.toml
```

This produces the recompiled game C++ under `port/generated/default/`. It is a
derivative work of your game; keep it out of git and do not distribute it.

### 8. Provide the native shaders

The native renderer needs the game's shaders converted to the host GPU's
format. They are generated from your own game; they are not in the repository.

- **From your own PC install:** copy the PC port's `native_shaders/` folder
  (it contains `shaders.spv.pak` for Vulkan and the loose metadata files).
- **From the PC port's converter:** the PC port's `tools/convert_shaders.py`
  and `pack_shaders.py` produce `native_shaders/shaders.spv.pak` from shaders
  captured while the game runs. See the PC port's README for the capture
  workflow.
- **deko3d branch:** additionally run
  `SPIRV_CROSS=/path/to/spirv-cross python3 tools/deko3d_shaders.py
  /path/to/native_shaders /path/to/native_shaders/deko3d` and copy
  `deko3d/shaders.dk.pak` beside `shaders.spv.pak`.

Copy the resulting `native_shaders/` folder to the SD card. Do not redistribute
it.

### 9. Build the NRO

```sh
tools/build_switch.sh --switch
```

By hand:

```sh
cmake -S port -B out/switch -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/Switch.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DREXSDK_DIR="$PWD/sdk" \
  -DPLUME_DIR="$PWD/third_party/plume" \
  -DREXGLUE_SWITCH_NVK_SDK="$REXGLUE_SWITCH_NVK_SDK" \
  -DREXGLUE_PLATFORM_SWITCH=ON \
  -DREXGLUE_ENABLE_TRACY=OFF \
  -DPLUME_PLATFORM_SWITCH=ON \
  -DPLUME_SWITCH_DEVKITPRO="$DEVKITPRO" \
  -DPLUME_SWITCH_NVK_LIBRARY="$REXGLUE_SWITCH_NVK_SDK/lib/libvulkan.a" \
  -DCMAKE_PREFIX_PATH="$DEVKITPRO/portlibs/switch"
cmake --build out/switch -j"$(nproc)"
```

The result is `out/switch/svr2011.nro` (about 77–82 MB) and the unstripped
`svr2011.elf`. The NRO contains the recompiled game code; do not upload it.

The current local build adds `-Wl,--allow-multiple-definition` because the
prebuilt NVK archive carries newlib gap fills (`getuid`) that the SDK
supplement also defines. A reproducible `mesa-switch` build may not need it.

### 10. Stage the SD card

The NRO needs the user's game data. Use the PC port's launcher to install the
game into a folder (it extracts the ISO and applies the `string.pac` /
`menu.pac` patches). On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools\stage_sd.ps1 `
    -GameDir "H:\Projects\SVR2011" -OutDir "H:\Projects\svr2011-sd"
```

Then copy the contents to:

```text
sdmc:/switch/svr2011/
```

The target layout:

```text
sdmc:/switch/svr2011/
  svr2011.nro              the program (built locally)
  svr2011.toml             settings (written on first start if missing)
  default.xex              your game's executable (user-supplied)
  pac/                     game data (user-supplied)
  sound/                   game data (user-supplied)
  movies/                  game data (user-supplied)
  plist360.arc             game data (user-supplied)
  plist360_4x3.arc         game data (user-supplied)
  native_shaders/          generated from your own game (user-supplied)
  pad_icons/               optional, from your own PC install
  Saves/                   created by the game
  Mods/                    optional, user-supplied .svrmod files
  DLC/                     optional, user-supplied DLC
  Music/                   optional, user-supplied entrance music
  Custom Movies/           optional, user-supplied entrance movies
```

Do not redistribute this folder. It contains game data.

### 11. First boot

Launch the NRO with a **title override** (hold **R** while starting an
installed game) or a forwarder configured for a **39-bit address space**.
Album applet mode does not give the game enough memory.

The first start compiles graphics pipelines; expect a stutter while the
shader/pipeline cache fills. The menus run at 60 fps. The `main` NVK build is
~20 fps in-ring on an overclocked console; the `deko3d` branch is the
performance path.

### 12. Troubleshooting

- **The NRO returns to the homebrew menu or crashes at start.** Check that
  you launched with a title override or forwarder, not album applet mode.
- **Black screen with audio.** Check `native_shaders/`; the native renderer
  needs the shader pack. The emulated renderer can be used as a fallback.
- **First-start stutter.** The driver compiles pipelines on first use; the
  pipeline cache on the SD card makes later sessions smoother.
- **NVK SDK not found.** Export `REXGLUE_SWITCH_NVK_SDK` and pass
  `-DPLUME_SWITCH_NVK_LIBRARY="$REXGLUE_SWITCH_NVK_SDK/lib/libvulkan.a"`.
- **Host codegen fails with a C++23 error.** Use a newer Clang (Ubuntu 24.04+
  or the LLVM apt packages); Ubuntu 22.04's default is too old.
- **The final link runs out of memory.** The LTO link of the recompiled game
  needs a lot of RAM; 32 GB is recommended.
- **The game hangs at the DLC prompt.** Keep `dlc_fan_axxess = false`.
- **Saving is slow or fails.** Use a folder save made by the PC build
  (`Saves/SaveData.dat/SaveData.Dat`); creating a flat save on the console is
  still unreliable.

---

## deko3d branch (performance)

```sh
git checkout deko3d
```

The deko3d branch replaces the Vulkan/NVK renderer with the Switch's own
deko3d API. It needs the devkitPro `deko3d` library and the vendored `uam`
shader compiler (both are built by the normal build; no extra download). The
shader pack is `shaders.dk.pak`, built by `tools/deko3d_shaders.py` as shown
above.

Set in `svr2011.toml`:

```toml
native_backend = "deko3d"
```

The app's Vulkan presenter is disabled automatically so deko3d owns the
NWindow. The app's Vulkan/ImGui overlays (settings, FPS overlay, achievements)
are not drawn on this path; the game's own UI is rendered by deko3d.

### Measured performance

In-ring, 60 Hz game logic:

| Build | CPU / GPU / RAM | In-ring | draw | span |
|---|---|---|---|---|
| NVK (`main`) | 1785 / 921.6 / 1866 MHz | ~20 fps | 8.6 ms | 49.8 ms |
| deko3d | 1963.5 / 998.4 / 1866 MHz | **35 fps** | 6.0 ms | 29.0 ms |
| deko3d | stock 1020 / 307.2 / 1331.2 MHz | **33 fps** | 6.3 ms | 30.2 ms |
| deko3d, `frame_rate=30` | 1963.5 / 998.4 / 1866 MHz | 30 fps | 7.7 ms | 33.3 ms |

- Menus run at 60 fps; heavy entrances (878–924 draws) drop to 15–21 fps.
- `frame_rate=30` is worse than 60: the game's 30 Hz world step does twice
  the work per frame. Use 60.
- FSR 1 (`native_upscale="fsr1"`, quality 4) is active at a 288p scene but
  does not change the CPU-limited fps.
- `-O3` for the generated code did not move the numbers; PGO instrumentation
  crashes at startup on the Switch and is not shipped.
- The main thread is the limit (97% of one A57 core); the phone's 60 fps in
  the Android build is its 3+ GHz big core and faster GPU.

---

## Controls and settings

The Switch port uses the game's Xbox 360 control layout. Set
`input_xbox_layout` in `svr2011.toml`:

- `true` (recommended): buttons by position, as on an Xbox pad — the Switch
  bottom button (B) is Xbox A, the right button (A) is Xbox B, the left (Y)
  is Xbox X, the top (X) is Xbox Y.
- `false`: by letter — Switch A is Xbox A, B is B, X is X, Y is Y.

The in-game menus, entrances and matches use the original game prompts.

Useful settings for low-memory / stock consoles:

```toml
native_render_scale = 0.5
native_texture_quality = "low"
native_shadows = false
native_scale_effects = true
arena_crowd = "off"
dlc_fan_axxess = false
switch_gpu_mhz = 0        # sys-clk controls the clocks
```

---

## Known issues

- The `main` NVK build is draw-bound at ~20 fps in-ring; use the `deko3d`
  branch for the 33–35 fps path.
- The app's Vulkan/ImGui overlays are not drawn on the deko3d path.
- The stock console is CPU-limited around 33 fps at 60 logic; 60 fps is not
  reachable on the Switch at stock clocks.
- Creating a save on the console is slow/unreliable; a PC-made folder save
  loads.
- The fake DLC package (`dlc_fan_axxess = true`) hangs the loader.
- PGO instrumentation crashes at startup; it is not shipped.

---

## Credits and licences

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE).

The port's own code is MIT. The ReXGlue SDK and the Horizon layer are
BSD-3-Clause. plume and its deko3d back end are MIT. uam is zlib/MIT/MPL-2.0.
Mesa/NVK is MIT. deko3d is zlib. The Bink reader/writer is
LGPL-2.1-or-later. SPIRV-Cross is Apache-2.0 (PC tool only). The AMD FidelityFX
FSR 1 shaders are MIT. No game material is covered by any of these licences.

This is an unofficial fan project. It is not affiliated with or endorsed by
WWE, THQ, Yuke's, Microsoft or Nintendo.
