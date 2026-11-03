# Building SVR2011-NX

This page describes the intended build. The Switch target is still being
wired (see [PORTING_PLAN.md](PORTING_PLAN.md)); the host code generator and
the third-party/portlib setup are usable now. Commands are for WSL2 Ubuntu
24.04/26.04 or a Linux machine.

> **Never add game data, `default.xex`, generated game C++, shader packs or a
> prebuilt NRO to the repository.** See [LEGAL.md](LEGAL.md). The release
> guard `tools/check_no_game_data.py` must pass.

## 1. Prerequisites

- **devkitPro** with:
  - devkitA64 (the Switch compiler),
  - libnx,
  - the Switch tools (`nacptool`, `elf2nro`),
  - deko3d (for the optional backend).
- CMake 3.25+, Ninja, Git, Python 3.10+, Clang/GCC.
- For Mesa/NVK: Meson, Ninja, Rust, `bindgen`, `cbindgen`, flex, bison,
  pkg-config, Python packages `packaging`, `setuptools`, `PyYAML`.
- 32 GB RAM recommended for the final LTO link of the recompiled game.
- Your own Xbox 360 copy of the game, and the right to use it.

On Ubuntu/WSL, the host tools can be installed with:

```sh
sudo apt update
sudo apt install -y build-essential cmake ninja-build clang lld git python3 \
  pkg-config flex bison libssl-dev
```

Install devkitPro from <https://devkitpro.org/wiki/Getting_Started>. The
scripts assume `DEVKITPRO=/opt/devkitpro`; set it if yours is elsewhere.

## 2. Fetch the ReXGlue third-party sources

The repository tracks only the third-party files this port changed. The rest
is fetched locally:

```sh
python3 tools/fetch_thirdparty.py
```

This clones ReXGlue SDK v0.10.0 and its submodules into a temporary folder and
copies the missing files into `sdk/thirdparty`. The fetched tree is ignored by
git. It needs network access and a few hundred MB of disk.

## 3. Build the Switch portlibs

NVK links against zlib, Expat and Zstandard. Build them for devkitA64:

```sh
sudo tools/build_portlibs.sh
```

By default they go into `$DEVKITPRO/portlibs/switch`. If you install them
elsewhere, set `PORTLIBS_PREFIX` and pass `-DCMAKE_PREFIX_PATH=<prefix>` to
the CMake configure.

## 4. Build Mesa/NVK for the Switch

The port uses [mesa-switch](https://github.com/danfromtico/mesa-switch), a
Mesa port for Horizon with NVK (Vulkan) and NAK (the shader compiler). Follow
that project's build instructions. The result is a folder containing:

```text
<mesa-sdk>/opt/devkitpro/portlibs/switch/lib/libvulkan.a
<mesa-sdk>/opt/devkitpro/portlibs/switch/include/vulkan/...
```

Set:

```sh
export REXGLUE_SWITCH_NVK_SDK=/path/to/mesa-sdk/opt/devkitpro/portlibs/switch
```

The build is Linux-oriented (a container or WSL is recommended). It is the
longest prerequisite. For a first link test, a prebuilt NVK archive may work,
but release builds should document and use a reproducible Mesa build.

## 5. Build the host code generator

```sh
tools/build_switch.sh --host
```

This configures `sdk/` in `out/host` and builds the `rexglue` code generator
with the host Clang. The tool runs on the PC; it is not part of the NRO.

If you prefer the commands by hand:

```sh
cmake -S sdk -B out/host -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DREXGLUE_USE_VULKAN=ON
cmake --build out/host --target rexglue -j"$(nproc)"
```

## 6. Provide your own game executable

Copy your own `default.xex` to:

```text
port/assets/default.xex
```

The file is ignored by git. Do not commit it. The code generator reads it to
produce `port/generated/default/` (also ignored).

## 7. Generate the game C++

```sh
tools/build_switch.sh --codegen
```

or:

```sh
cd port
../out/host/rexglue codegen svr2011_manifest.toml
```

This produces the recompiled game C++ under `port/generated/default/`. It is a
derivative work of your game; keep it out of git and do not distribute it.

## 8. Build the NRO

The Switch target is wired. The command is:

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

The result is `out/switch/svr2011.nro` (about 66 MB) and the unstripped
`svr2011.elf`. The NRO contains the recompiled game code; do not upload it.

The current local build uses the public prebuilt `nvk-switch` archive for the
first link. The port adds `-Wl,--allow-multiple-definition` because that
archive carries newlib gap fills (`getuid`) that the SDK supplement also
defines. A release build should use a reproducible `mesa-switch` build; if it
does not carry those gap fills, remove that link option.

The NRO has not been run on hardware yet. See [TESTING.md](TESTING.md).

## 9. Prepare the SD card

The NRO needs the user's game data. Use the PC port's launcher to install the
game into a folder (it extracts the ISO and applies the `string.pac` /
`menu.pac` patches), then copy the folder to:

```text
sdmc:/switch/svr2011/
```

The layout is described in the top-level `README.md`. At minimum:

- `svr2011.nro`
- `svr2011.toml`
- `default.xex`
- `pac/`, `sound/`, `movies/`, `plist360.arc`, `plist360_4x3.arc`
- `native_shaders/` generated from your own game, or copied from your own PC
  install
- `pad_icons/` (optional, from your own PC install)

Launch the NRO with a **title override** (hold **R** while starting an
installed game) or a forwarder configured for a **39-bit address space**.
Album applet mode does not give the game enough memory.

## 10. Troubleshooting

- **The NRO returns to the homebrew menu / crashes at start.** Check that
  you launched with a title override or forwarder, not album applet mode.
- **Black screen with audio.** Check `native_shaders/`; the native renderer
  needs the shader pack. The emulated renderer can be used as a fallback.
- **First-start stutter.** The driver compiles pipelines on first use; the
  shader/pipeline cache on the SD card makes later sessions smoother.
- **No controller.** Check the Switch input driver mapping and the
  `input_backend` setting.
- **Out of memory.** The game needs the application memory budget, not the
  applet budget. Close other apps and use a forwarder/title override.
- **The build runs out of RAM.** The LTO link is large; close other programs
  or use a machine with 32 GB.

## Release checklist

1. `python3 tools/check_no_game_data.py` passes.
2. No `port/generated/`, `native_shaders/`, `.nro`, game files or screenshots
   are tracked.
3. Release notes state the bring-your-own-game model and the title-override
   requirement.
4. The release contains source and build/installer tools only. Do not attach
   a prebuilt NRO with the recompiled game code.
