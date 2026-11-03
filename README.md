# SVR2011-NX

**WWE SmackDown vs. Raw 2011 - Nintendo Switch homebrew port (work in progress).**

This is a native Nintendo Switch homebrew port of the Xbox 360 version of
*WWE SmackDown vs. Raw 2011*. It is not an emulator: the game's PowerPC code
is statically recompiled to C++ with [ReXGlue](https://github.com/rexglue/rexglue-sdk)
and compiled for the Switch with devkitA64/libnx. The native renderer draws
through Vulkan on [Mesa NVK](https://github.com/danfromtico/mesa-switch); a
deko3d backend is planned for the performance pass.

The port is based on the public
[WWE SmackDown vs. Raw 2011 PC port](https://github.com/KaikoClanworth1/wwe-svr2011-pc)
by KaikoClanworth1 and contributors, and on the Horizon (Switch) layer of the
public NFSMW-NX and SA2-NX ReXGlue ports.

> **Status: first buildable NRO, not yet playable.** The source now builds a
> 66 MB `svr2011.nro` for Switch with devkitA64 + NVK. It has not been run on
> hardware yet; the next milestone is the first boot test. See
> [docs/PORTING_PLAN.md](docs/PORTING_PLAN.md) and
> [docs/TESTING.md](docs/TESTING.md).

---

## No game material

This repository contains **no game data and no recompiled game code**.

You need your own legally obtained Xbox 360 copy of *WWE SmackDown vs. Raw
2011* (the USA/Europe multi-language disc image, or its extracted
`default.xex` and game files). The NRO is generated locally from that copy.
The release artifacts for this project are source and build/installer tools,
not a playable NRO containing the game.

Do not open issues or pull requests that attach an ISO, `default.xex`, game
files, shader packs, textures, audio, video, screenshots of the game, or a
prebuilt NRO. See [docs/LEGAL.md](docs/LEGAL.md).

---

## What works

| Area | State |
|---|---|
| Source import from the PC port (MIT) | Done |
| Horizon (Switch) ReXGlue SDK layer | Imported (BSD-3-Clause) |
| Build scaffolding and third-party fetch | Done |
| Host code generator (`rexglue`) from the user's `default.xex` | Done (403 generated files) |
| Switch portlibs + NVK + Vulkan build | Done (compiles) |
| Switch NRO target | **Builds** (66 MB `svr2011.nro`); hardware test pending |
| Mesa/NVK + Vulkan presentation | Wired and compiled; hardware test pending |
| Boot to the main menu | Not yet |
| Match, audio, input, saves | Not yet |
| Performance pass (30 fps target) | Not yet |
| Installer / release packaging | Not yet |

---

## Requirements

- A Nintendo Switch 1 (Erista or Mariko) with Atmosphère/homebrew support.
  Switch 2 homebrew is a separate, less mature target and is not covered here.
- Your own Xbox 360 copy of the game and a way to read it (ISO or extracted
  files). About 5.4 GB of game data plus the ISO.
- A microSD card with enough free space (8 GB minimum; 16 GB recommended).
- A PC with:
  - WSL2 Ubuntu 24.04/26.04 or a Linux machine (the build scripts target
    Linux; Windows-native builds are possible but not documented yet).
  - devkitPro with devkitA64, libnx and the Switch tools.
  - CMake 3.25+, Ninja, Git, Python 3.10+, Clang/GCC.
  - 32 GB RAM recommended for the LTO build of the recompiled game.
  - For Mesa/NVK: the Mesa build prerequisites (Meson, Ninja, Rust, bindgen,
    cbindgen, flex, bison, pkg-config).
- A title override (hold **R** while starting an installed game) or a
  forwarder with a **39-bit address space**. Album applet mode does not give
  the game enough memory.

---

## Build overview

The full instructions are in [docs/BUILDING.md](docs/BUILDING.md). The short
version:

```sh
# 1. Fetch the ReXGlue third-party sources (not committed)
python3 tools/fetch_thirdparty.py

# 2. Build the Switch portlibs (zlib, expat, zstd) into devkitPro
sudo tools/build_portlibs.sh

# 3. Build Mesa/NVK for the Switch (see docs/BUILDING.md)
#    and set REXGLUE_SWITCH_NVK_SDK to its portlibs/switch folder.

# 4. Put your own default.xex in port/assets/ (ignored by git)
cp /path/to/your/game/default.xex port/assets/default.xex

# 5. Build the host code generator and generate the game C++
tools/build_switch.sh --codegen

# 6. Build the NRO (once the Switch target is wired)
tools/build_switch.sh --switch
```

The first build is long. The game's recompiled code is large, and the final
LTO link needs a lot of RAM. The first start on the console also compiles
graphics pipelines; expect a stutter while the shader cache fills.

---

## SD card layout

Once the NRO is built, the target layout is:

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
  native_shaders/          generated from your own game, or copied from
                           your own PC install (user-supplied)
  pad_icons/               optional, from your own PC install
  Saves/                   created by the game
  Mods/                    optional, user-supplied .svrmod files
  DLC/                     optional, user-supplied DLC
  Music/                   optional, user-supplied entrance music
  Custom Movies/           optional, user-supplied entrance movies
```

Do not redistribute this folder. It contains game data.

---

## Controls

The Switch port uses the game's Xbox 360 control layout. The default mapping
is by letter (Switch A = Xbox A, B = B, X = X, Y = Y); a position-based
mapping is planned as a setting. The in-game menus, entrances and matches use
the original game prompts.

---

## Credits and licences

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE).

The port's own code is MIT. The ReXGlue SDK and the Horizon layer are
BSD-3-Clause. plume is MIT. Mesa/NVK is MIT. deko3d is zlib. The Bink
reader/writer is LGPL-2.1-or-later. No game material is covered by any of
these licences.

This is an unofficial fan project. It is not affiliated with or endorsed by
WWE, THQ, Yuke's, Microsoft or Nintendo.
