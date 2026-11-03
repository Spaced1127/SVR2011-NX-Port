# Distribution model

SVR2011-NX is a **bring-your-own-game** project. The public release is a
builder, not a playable NRO.

## Why the release is a builder

The NRO contains the recompiled game code generated from `default.xex`. That
code is a derivative work of the game, even when every texture, sound, movie
and menu asset is read from the user's own extracted folder. The shader pack is
generated from the game's shaders and is derivative too. Distributing either
would be distributing the game's material.

So the release contains:

| Artifact | In the release? | Why |
|---|---|---|
| Port source, patches, tools, docs | Yes | MIT / BSD-3-Clause |
| `tools/build_release.ps1`, `tools/stage_sd.ps1` | Yes | This project's code |
| Open-source toolchain downloads (devkitPro, NVK) | Downloaded at build time | Their own licences |
| `svr2011.nro` | **No** | Contains the recompiled game code |
| `native_shaders/` | **No** | Generated from the game's shaders |
| `default.xex`, `pac/`, `sound/`, `movies/` | **No** | The game itself |
| Saves, DLC, mods, music, custom movies | **No** | User material |

The NRO is produced locally from the user's own copy. The release is source
and build tools only, which is the policy in [LEGAL.md](LEGAL.md).

## What the user needs

- Windows 10/11 with WSL2 (Ubuntu 22.04, 24.04 or 26.04).
- devkitPro with devkitA64, libnx and switch-tools. The builder checks for it
  and prints the install link if it is missing.
- About 10 GB free disk (toolchain, source, generated code and build tree).
- An internet connection for the first build.
- Their own Xbox 360 copy of the game, installed into a folder with the PC
  port's launcher: `default.xex`, `pac/`, `sound/`, `movies/`,
  `plist360.arc`, `plist360_4x3.arc`, `native_shaders/`.

## Build with the release

1. Download and extract the release zip.
2. Run `Build SVR2011-NX.cmd`.
3. Select the extracted game folder (the one with `default.xex`, `pac`,
   `sound` and `movies`).
4. Wait. The first build takes 15-40 minutes; later builds are incremental.
5. The builder leaves an SD folder in
   `%LOCALAPPDATA%\SVR2011-NX\dist`. Copy its **contents** to
   `sdmc:/switch/svr2011/` on the SD card.
6. Launch with a title override (hold **R** while starting an installed game)
   or a forwarder with a 39-bit address space. Album applet mode does not give
   the game enough memory.

The builder:

- copies the release source to `%LOCALAPPDATA%\SVR2011-NX\work\src`;
- installs the Linux build packages and checks devkitPro;
- builds zlib, Expat and Zstandard for devkitA64;
- downloads the pinned NVK archive;
- builds the host `rexglue` code generator;
- runs `rexglue codegen` on the user's `default.xex`;
- builds `svr2011.nro`;
- stages the SD folder and verifies the file counts.

It does **not** upload anything. The generated NRO and game data stay on the
user's PC.

## Manual build

The same steps are documented for developers in [BUILDING.md](BUILDING.md).
The one-click builder is a wrapper around `tools/setup_wsl.sh`,
`tools/build_switch.sh --nro` and `tools/stage_sd.ps1`.

## Release checklist

Before publishing a GitHub release:

1. `python tools/check_no_game_data.py` passes on the committed tree.
2. The release zip is made from `git archive` (tracked files only), so
   `port/generated/`, `port/assets/default.xex`, `third_party/nvk/`,
   `sdk/thirdparty/`, `out/` and `dist/` are absent.
3. The zip contains no `.nro`, `.xex`, `.iso`, `.pac`, `.bik`, `.spv.pak`,
   textures, audio, video, saves or screenshots.
4. Release notes state the bring-your-own-game model and the title-override
   requirement.
5. Do not attach a prebuilt NRO, a shader pack, or a zip of the staged SD
   folder to the release.

`tools/package_release.ps1` runs the guard, creates the zip from `git archive`
and verifies the zip contents.

## Trademarks and licences

The port's own code is MIT. The ReXGlue SDK and Horizon layer are
BSD-3-Clause. plume is MIT. Mesa/NVK is MIT. devkitPro components keep their
own licences. The game is not licensed by this project. See
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and [LEGAL.md](LEGAL.md).
