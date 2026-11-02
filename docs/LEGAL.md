# Legal and release policy

SVR2011-NX is a **bring-your-own-game** project. The repository and its
releases must never contain material that belongs to the game's owners.

## Never commit or upload

- the Xbox 360 disc image (`.iso`), `default.xex`, or any extracted game file;
- `pac/`, `sound/`, `movies/`, `plist360*.arc`, `pad_icons/`, DLC, texture
  packs, mods that contain game assets, saves, music or custom movies;
- `native_shaders/` or any shader pack generated from the game's shaders;
- `port/generated/` (the recompiled game C++), `svr2011.exe`, `libmain.so`,
  `rexruntime.dll`, `rexgpu-xenos.dll`, or any prebuilt game binary;
- a prebuilt `.nro`, `.nsp` or `.xci` that contains the recompiled game code;
- screenshots, box art, logos, fonts, audio or video from the game;
- the PC port's release zip, the Android APK, or the game data folder.

`tools/check_no_game_data.py` is the release guard. It must pass before a
commit is tagged or a release is published.

## What a release may contain

The recommended release is **source + build/installer tools only**:

- this repository's source, patches, documentation and scripts;
- third-party sources fetched by the user at build time;
- an installer page or script that reads the user's own game copy and
  generates the game files, shader library and NRO locally.

A release must not contain a ready-to-play NRO with the recompiled game code,
because that code is a derivative work of the game. If the project later
decides to distribute a prebuilt NRO, that decision needs a legal review
first; the current policy is source-only.

## User responsibilities

The user must:

- own a legal copy of the Xbox 360 game;
- make their own disc image or extracted files;
- comply with the game's licence and local law;
- not share the generated game data, shader packs or NRO.

## Licences

| Component | Licence |
|---|---|
| This port's own code | MIT (`LICENSE`) |
| ReXGlue SDK | BSD-3-Clause (`sdk/LICENSE`) |
| Horizon (Switch) SDK layer | BSD-3-Clause |
| plume | MIT (`third_party/plume/LICENSE`) |
| Mesa/NVK | MIT (Mesa per-file licences) |
| deko3d | zlib |
| uam | zlib / MIT / MPL-2.0 |
| XenosRecomp | MIT |
| FFmpeg / Bink reader | LGPL-2.1-or-later |
| libmspack | LGPL-2.1 |
| libnx | ISC |
| Game | not licensed by this project |

Do not copy GPL-3.0 application code from other ports into this MIT project.
The Horizon SDK layer used here is BSD-3-Clause; keep that separation.

## Trademarks

WWE, SmackDown, Raw and all related names and logos belong to their owners.
THQ / Yuke's own the original game. Nintendo Switch and Xbox 360 are
trademarks of Nintendo and Microsoft. This project is unofficial and not
endorsed by any of them.
