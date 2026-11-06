# WWE SmackDown vs. Raw 2011 — Nintendo Switch deko3d port

**Release notes · `deko3d` branch (repository default) · Game_files layout**

| | |
|---|---|
| Build | `deko3d` branch, save-fix build (2026-11-06) |
| File | `svr2011.nro` |
| Size | 82,774,213 bytes |
| SHA-256 | `40BA4887C52DE7B02A43BC84817E039C9E1713EB29060C02F0A59FCC927D8D15` |
| Game version | WWE SmackDown vs. Raw 2011, Xbox 360 (2.1.8, US/EU multi-language) |
| Requires | Your own copy of the game; Switch 1 with Atmosphère/homebrew |

> **The game data is not included.** This release provides the compiled port.
> You must supply your own `default.xex`, `pac/`, `sound/`, `movies/` and the
> other files from your legally owned Xbox 360 copy. The `Game_files/` folder
> is your own data: do not upload or share it. See [Legal](#legal).

---

## What this is

A native Nintendo Switch homebrew port of the Xbox 360 version of *WWE
SmackDown vs. Raw 2011*. The game's PowerPC code is recompiled to C++ with
[ReXGlue](https://github.com/rexglue/rexglue-sdk); the renderer uses the
Switch's own **deko3d** GPU API. It is not an emulator and needs no custom
firmware beyond Atmosphère/homebrew support.

What works in this build:

- boots to the menu; 60 fps menus;
- a 1v1 match from the entrance to the pinfall, celebration and results;
- audio, controller input and the game's own UI;
- loading a folder save and overwriting it; the flat-save mount now copies the
  save with stdio on the SD (no hard links, `copy_file` is `ENOSYS` there);
- the system Capture-button screenshots (the earlier in-ring freeze is fixed);
- **~51 fps in-ring** on the overclocked console (50.8–55.4 fps over five-second
  windows in the reference log; 60 Hz game logic, draw 3.7 ms, span 19.4 ms).

Not enabled in this profile: instant replays / match-end highlight replays and
the optional arena crowd. See [Known issues](#known-issues).

---

## What you need

- A Nintendo Switch 1 (Erista or Mariko) with Atmosphère and a way to launch
  homebrew (title override or forwarder; album applet mode does not give the
  game enough memory).
- Your own Xbox 360 copy of the game, as an ISO (XDVDFS) or as the files the
  PC port's launcher installed (`default.xex`, `pac/`, `sound/`, `movies/`, ...).
- About 6 GB free on the microSD card.
- The **deko3d shader pack** generated from your own copy
  (`Game_files/native_shaders/shaders.dk.pak`). It is not included in this
  release; [Step 2](#step-2--the-deko3d-shader-pack) shows how to make it.
- On Windows, PowerShell 5.1+ for the optional staging/verification scripts.

---

## SD card layout

Copy this structure to the SD card (the folder name and case are not magic, but
keep `Game_files` beside the NRO):

```text
sdmc:/switch/SVR2011/
  Game_files/
    default.xex
    nxeart
    plist360.arc
    plist360_4x3.arc
    pac/
    sound/
    movies/
    native_shaders/
      shaders.spv.pak       (input for the converter)
      shaders.dk.pak        (the deko3d pack the NRO reads)
      pipelines.list
    pad_icons/              (optional)
    Mods/                   (optional)
    DLC/                    (optional)
    Music/                  (optional)
    Custom Movies/          (optional)
  svr2011.nro
  svr2011.toml
  Saves/                    (created by the port)
  UserData/                 (created by the port)
  logs/                     (created by the port)
```

The NRO finds `Game_files/` beside itself. Without that folder it falls back
to the old “disc files beside the NRO” layout, but this release is built and
tested for `Game_files/`.

---

## Step 1 — put your own game files in `Game_files`

You can use either a disc image or an existing PC-port install.

### Option A: Xbox 360 ISO (XDVDFS)

From the repository, extract your own image:

```sh
python3 tools/extract_iso.py "path/to/game.iso" "extracted-game"
```

The tool only reads the disc image; it writes the disc's files to
`extracted-game`. Then copy these into `Game_files`:

```text
default.xex
nxeart
plist360.arc
plist360_4x3.arc
pac/
sound/
movies/
pad_icons/        (if present)
```

On Windows, `robocopy` is much faster for the folders:

```powershell
robocopy "extracted-game\pac"     "SVR2011\Game_files\pac"     /E
robocopy "extracted-game\sound"   "SVR2011\Game_files\sound"   /E
robocopy "extracted-game\movies"  "SVR2011\Game_files\movies"  /E
Copy-Item "extracted-game\default.xex"       "SVR2011\Game_files\" -Force
Copy-Item "extracted-game\nxeart"            "SVR2011\Game_files\" -Force
Copy-Item "extracted-game\plist360.arc"      "SVR2011\Game_files\" -Force
Copy-Item "extracted-game\plist360_4x3.arc"  "SVR2011\Game_files\" -Force
```

`tools/discfs.py` can read an image directly and copy one disc folder at a
time (the destination folder receives that folder's contents):

```sh
python3 tools/discfs.py get "path/to/game.iso" pac   "SVR2011/Game_files/pac"
python3 tools/discfs.py get "path/to/game.iso" sound "SVR2011/Game_files/sound"
python3 tools/discfs.py get "path/to/game.iso" movies "SVR2011/Game_files/movies"
python3 tools/discfs.py get "path/to/game.iso" default.xex "SVR2011/Game_files"
```

### Option B: the files from the PC port's install

If the PC port's launcher installed the game, its install folder already
contains the required files. Copy these into `Game_files`:

```text
default.xex
nxeart
plist360.arc
plist360_4x3.arc
pac/
sound/
movies/
pad_icons/        (if present)
native_shaders/   (see Step 2)
```

Do **not** copy the PC install's `Saves/`, `UserData/`, `logs/`, `launcher.ini`,
`nvngx_dlss.dll`, `NVIDIA DLSS licence.txt`, `playtime.txt` or its
`svr2011.toml`/NRO. Only the game files above and the shader folder belong in
`Game_files`.

### Optional folders

If you want mods, DLC, custom entrance music or custom entrance movies, put
them in `Game_files/Mods`, `Game_files/DLC`, `Game_files/Music` and
`Game_files/Custom Movies` respectively. They are read from the game data
folder, not from beside the NRO.

---

## Step 2 — the deko3d shader pack

The `native_shaders` folder is **not** on the game disc. The PC port's launcher
generates it from your copy (`shaders.spv.pak`, `pipelines.list`, and the PC
DirectX packs). The Switch deko3d renderer needs a converted **`shaders.dk.pak`**
made from those files.

1. Copy the PC install's `native_shaders` folder to
   `Game_files/native_shaders`. It must contain at least `shaders.spv.pak` and
   `pipelines.list`.

2. Build SPIRV-Cross once (the converter is a PC tool):

   ```sh
   git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Cross
   cmake -S SPIRV-Cross -B SPIRV-Cross/build -G Ninja -DCMAKE_BUILD_TYPE=Release
   ninja -C SPIRV-Cross/build spirv-cross
   ```

3. Convert the shaders:

   ```sh
   SPIRV_CROSS=/path/to/spirv-cross/build/spirv-cross \
     python3 tools/deko3d_shaders.py \
       "SVR2011/Game_files/native_shaders" \
       "SVR2011/Game_files/native_shaders/deko3d"
   ```

   On Windows (PowerShell), set the variable first:

   ```powershell
   $env:SPIRV_CROSS = "C:\path\to\spirv-cross.exe"
   python tools\deko3d_shaders.py "SVR2011\Game_files\native_shaders" `
                                  "SVR2011\Game_files\native_shaders\deko3d"
   ```

   The converter writes
   `SVR2011/Game_files/native_shaders/deko3d/shaders.dk.pak`. Copy it beside
   the input pack:

   ```powershell
   Copy-Item "SVR2011\Game_files\native_shaders\deko3d\shaders.dk.pak" `
             "SVR2011\Game_files\native_shaders\shaders.dk.pak" -Force
   ```

   (On Linux/macOS use `cp`.)

4. If you already have a `shaders.dk.pak` made from your own copy, copy it to
   `Game_files/native_shaders/shaders.dk.pak`. Do not use someone else's shader
   pack; it is derived from the game's shaders.

The NRO reads `Game_files/native_shaders/shaders.dk.pak` at startup. If it is
missing, the screen stays black (the log says the native renderer's shaders are
missing).

---

## Step 3 — copy the NRO and the settings

```text
SVR2011/svr2011.nro      the file from this release
SVR2011/svr2011.toml     the settings below (or your own)
SVR2011/Game_files/      your own game data and shader pack
```

The measured profile (also in the repository's
`docs/performance-svr2011.toml`):

```toml
# WWE SmackDown vs. Raw 2011 - Nintendo Switch settings.
gpu_plugin = "xenos"
native_renderer = "main"
gpu_backend = "vulkan"
input_backend = "switch"
resolution = "720p"
resolution_scale = 1
fullscreen = true
vsync = true
native_max_scale = 1
native_2x_msaa = false
native_prepare_pipelines = true
native_texture_quality = "low"
native_scale_effects = true
native_render_scale = 0.5
native_upscale = "off"
native_record_thread = true
switch_gpu_mhz = 0
input_xbox_layout = true
native_shadows = false
arena_crowd = "off"
depth_of_field = false
motion_blur = false
unlock_everything = false
replays = false
dlc_fan_axxess = false
svr2011_watchdog_dump = true
nfsmw_io_ventana_kb = 1024
nfsmw_io_ventanas_max = 32
nfsmw_io_cache_mb = 64
nfsmw_io_rangos_mb = 32
native_resolve_write_back = false
```

Notes:

- `switch_gpu_mhz = 0` leaves the clocks to sys-clk. The reference console runs
  CPU 1963.5 / GPU 998.4 / RAM 2133 MHz. Use `460` for the official handheld
  GPU profile if you do not overclock.
- `replays = false` is required for the stable profile. Replays and the
  match-end highlight replays are not supported in this build; the match still
  reaches the celebration and results.
- `arena_crowd = "off"` is the measured setting. The crowd is a GPU cost and is
  not part of the supported profile.
- If `svr2011.toml` is missing, the NRO writes conservative defaults; the
  profile above is the measured one.

---

## Step 4 — verify the copy (optional but recommended)

On Windows, from the repository:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify_sd.ps1 -SdDir "SVR2011"
```

It checks the NRO, the TOML, `Game_files/`, the required files and the
`pac` (265), `sound` (8) and `movies` (87) file counts. A copy that passes is
complete; it does not read the whole 5.5 GB.

Manual minimum:

```text
Game_files/default.xex
Game_files/nxeart
Game_files/plist360.arc
Game_files/plist360_4x3.arc
Game_files/pac/            (265 files)
Game_files/sound/          (8 files)
Game_files/movies/         (87 files)
Game_files/native_shaders/shaders.dk.pak
Game_files/native_shaders/pipelines.list
```

---

## Step 5 — launch

1. Copy `SVR2011` (or its contents) to `sdmc:/switch/SVR2011/`.
2. Launch the NRO with a **title override** (hold **R** while starting an
   installed game) or a forwarder configured for a **39-bit address space**.
   Album applet mode does not give the game enough memory.
3. The first start compiles graphics pipelines and shaders; expect a stutter
   while that finishes. Later starts are faster.

The first log lines include:

```text
game folder: .../SVR2011/Game_files
```

If it still says the NRO's own folder, `Game_files/` is not beside the NRO or
the name is wrong.

---

## Performance

Measured on Switch hardware, handheld, 720p, 60 Hz game logic:

| | |
|---|---|
| In-ring | **50.8–55.4 fps** over five-second windows (reference `107` log) |
| Draw | 3.7 ms per frame |
| Span | 19.4 ms |
| Clocks | CPU 1963.5 / GPU 998.4 / RAM 2133 MHz |
| Menus | 60 fps |

The main thread is the limit. Stock clocks measured ~33 fps in the earlier
build; 60 fps in-ring is not reachable at stock clocks. FSR 1 was measured
slower than the no-FSR 0.5 scene profile, so the measured profile keeps
`native_upscale = "off"` and `native_render_scale = 0.5`.

---

## Controls

The Switch port uses the game's Xbox 360 layout. With
`input_xbox_layout = true` (recommended):

- Switch bottom button (B) = Xbox A
- Switch right button (A) = Xbox B
- Switch left button (Y) = Xbox X
- Switch top button (X) = Xbox Y

Set it to `false` to map by letter instead. The libnx pad driver is the only
input backend built (`input_backend = "switch"`).

---

## Known issues

- **Replays and match-end highlight replays are off.** The recorder costs CPU
  and was the match-start crash; `replays = false` is the stable path. After a
  pinfall the match still reaches the celebration and results, without the
  replay.
- **The optional arena crowd is off** in the measured profile
  (`arena_crowd = "off"`). It costs GPU time and is not part of the supported
  profile.
- **Saves**: the flat `Saves/SaveData.dat` mount now copies the save with
  stdio on the SD (the Switch's filesystem has no hard links and
  `std::filesystem::copy_file` is `ENOSYS` there). The folder save
  `Saves/SaveData.dat/SaveData.Dat` remains the safest form; if a save from an
  older build still fails, convert it to the folder form (see Troubleshooting).
- **DLC:** the port's fake Fan Axxess package hangs the DLC loader; keep
  `dlc_fan_axxess = false` and `unlock_everything = false`.
- **Vulkan/ImGui overlays** (settings, FPS overlay, achievements) are not drawn
  on the deko3d path; the game's own UI is rendered.
- **PGO** is not shipped; the instrumented NRO crashes at startup.
- The first start after a fresh shader cache can stutter while pipelines
  compile.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Returns to the Homebrew Menu | Launched in applet mode, or an early exception; use a title override/forwarder and read `logs/rex/`. |
| Black screen, no audio | Missing `Game_files/native_shaders/shaders.dk.pak` or missing game files; check the log for “shaders are missing” / “game files”. |
| Black screen with audio | Renderer/presenter issue; the log's GPU report and swapchain lines matter. |
| “game files missing” | `Game_files/` lacks `default.xex`, `pac/`, `sound/`, `movies/`, `plist360*.arc` or `nxeart`; re-copy them. |
| No controller | `input_backend` must be `switch`; the libnx pad driver is the only one built. |
| Out of memory | You are in album applet mode; use a title override/forwarder. |
| Hangs while loading a save | The save is the flat `Saves/SaveData.dat` file. Use the folder form: create a folder `Saves/SaveData.dat`, move the flat file into it as `SaveData.Dat`, and delete `Saves/.mount`. The folder save loads. |
| “game folder” line points at the NRO folder | `Game_files/` is not beside the NRO or is named differently. |

Logs and crash reports are written beside the NRO, under `logs/`
(`SVR2011/logs/rex/`). Send the whole log, not only the last line; the
`game folder:` line and the shader/game-file lines show how far it got. Do not
attach game data, `default.xex`, the NRO or the shader pack to a public issue.

---

## Legal

You must own a legally obtained copy of *WWE SmackDown vs. Raw 2011* for the
Xbox 360. This release does not include the game's data files (`pac/`, `sound/`,
`movies/`), saves, DLC or the shader pack; you supply all of those from your own
copy. The `Game_files/` folder is your own game data and must not be uploaded or
shared.

The NRO is built from the port and the game code generated from your own
`default.xex`; use it only with your own copy. This project is not affiliated
with WWE, THQ, 2K, Nintendo or the game's other rights holders. *WWE SmackDown
vs. Raw 2011* and its assets are trademarks and copyrights of their owners.

---

## Credits and licenses

- [ReXGlue](https://github.com/rexglue/rexglue-sdk) (BSD-3-Clause) and the
  Horizon/Switch layer from the public NFSMW-NX and SA2-NX ports.
- The public [WWE SmackDown vs. Raw 2011 PC port](https://github.com/KaikoClanworth1/wwe-svr2011-pc)
  (MIT) by KaikoClanworth1 and contributors, which this Switch port is based on.
- [plume](https://github.com/banjo-nx/plume) and its deko3d back end (MIT),
  [uam](https://github.com/devkitPro/uam) (zlib/MIT/MPL-2.0), and deko3d
  (zlib, devkitPro).
- devkitPro, devkitA64, libnx and switch-tools.
- [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) (Apache-2.0) for
  the shader conversion; AMD FidelityFX FSR 1 shaders (MIT) where used.

The port source and license notices are in the repository. No game assets are
distributed with the source; maintainer screenshots are documentation only.
