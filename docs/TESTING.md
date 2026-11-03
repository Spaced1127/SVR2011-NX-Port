# First hardware test

The first `svr2011.nro` builds, but it has **not been run on a Switch yet**.
This page is the checklist for the first boot. Expect to find problems; the
goal is to get a log and the first frame, then fix them one at a time.

## What you need

- A Nintendo Switch 1 with Atmosphère and the Homebrew Menu.
- A title override or a forwarder with a **39-bit address space**. Album
  applet mode does not give the game enough memory.
- Your own Xbox 360 game data, installed with the PC port's launcher (or an
  equivalent extraction of the disc).
- The PC port's `native_shaders` folder (at least `shaders.spv.pak` and
  `pipelines.list`), copied from your own install.
- The `svr2011.nro` from `out/switch/`.

## Assembling the folder on Windows

If the game is already installed in a PC folder (the layout the PC port uses),
`tools/stage_sd.ps1` copies the right files and writes a Switch settings file:

```powershell
powershell -ExecutionPolicy Bypass -File tools\stage_sd.ps1 `
    -GameDir "H:\Projects\SVR2011" `
    -Nro "out\switch\svr2011.nro" `
    -OutDir "H:\Projects\svr2011-sd"
```

Add `-DryRun` to see the sizes without copying, and `-IncludeOptional` to also
take `Mods`, `DLC`, `Music` and `Custom Movies` if they exist. The output folder
must stay outside the repository, and it must never be uploaded or shared.

After copying to the SD card, check it before launching:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify_sd.ps1 `
    -SdDir "E:\switch\svr2011" `
    -StageDir "H:\Projects\svr2011-sd"
```

It checks the required files and the `pac` (265), `sound` (8) and `movies`
(87) file counts. If the game logs "360 of the disc's files missing" with a
list starting at `movies\logo.bik`, the `pac`, `sound` and `movies` folders
did not finish copying: wait for the copy to finish and run the verifier
again.

## SD card layout

```text
sdmc:/switch/svr2011/
  svr2011.nro
  svr2011.toml              (delete the PC one for the first test; see below)
  default.xex
  nxeart
  plist360.arc
  plist360_4x3.arc
  pac/
  sound/
  movies/
  pad_icons/                (optional, from your own PC install)
  native_shaders/           (shaders.spv.pak, pipelines.list)
  Saves/                    (created by the game)
  Mods/                     (optional)
  DLC/                      (optional)
```

Do not redistribute this folder. It contains game data.

## Settings for the first test

If you copy a PC `svr2011.toml`, change these values (or delete the file and
let the NRO write its Switch defaults):

```toml
gpu_plugin = "xenos"
native_renderer = "main"
gpu_backend = "vulkan"
input_backend = "switch"
resolution = "720p"
resolution_scale = 1
fullscreen = true
vsync = true
```

The Switch build's default config is Vulkan, the libnx pad driver, 720p and
fullscreen. A PC config with `input_backend = "xinput"` is not valid on
Switch.

## Launch

1. Copy the folder to the SD card.
2. Hold **R** while starting an installed game, or use your forwarder, to get
   the full application memory.
3. Start `svr2011.nro` from the Homebrew Menu.

## What to check

- Does the NRO start at all (a window / black screen / crash)?
- Does it reach the game's first logo or main menu?
- Is there audio?
- Does the controller work in the menu?
- Does the game find its data, or log missing files?

## Logs

The SDK writes its log and crash reports beside the NRO, under `logs/`
(typically `sdmc:/switch/svr2011/logs/rex/`). If the NRO returns to the
Homebrew Menu or the console shows an error, copy:

- the newest file in `logs/` (or `logs/rex/`),
- `svr2011.toml`,
- the Atmosphère crash report if one was shown,
- your Switch model, firmware version, and whether it was docked or handheld.

Send the **whole log file**, not only the last error line: the `game folder:`
line near the top shows which directory the NRO used, and the GPU/audio/input
lines show how far it got. Do not attach the game data, `default.xex`, the NRO,
or shader packs to a public issue. The log and settings are enough.

## Likely first-boot failures

| Symptom | Check |
|---|---|
| Returns to the Homebrew Menu immediately | Launched in applet mode, or the NRO hit an early exception; use a title override/forwarder and read `logs/`. |
| Black screen, no audio | Missing `native_shaders/shaders.spv.pak`; missing game files; check the log for the renderer/game-file messages. |
| Black screen with audio | Renderer/presenter issue; the log's GPU report and swapchain lines matter. |
| "game files missing" | The game folder lacks `default.xex`, `pac/`, `sound/`, `movies/`, `plist360*.arc` or `nxeart`; reinstall with the PC launcher. |
| No controller | `input_backend` must be `switch`; the libnx pad driver is the only one built. |
| Out of memory / thread creation failure | Use a forwarder or title override; close other software. |
| Crash after a few seconds | Copy `logs/rex/rex_crash.log` and the Atmosphère report. |

## After the first boot

Once the game reaches a menu, the next milestones are an exhibition match,
audio, saves, the 30 fps mode and profiling. See
[PORTING_PLAN.md](PORTING_PLAN.md).
