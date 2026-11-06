# Current state

Updated 2026-11-05, after the first full match on hardware.

## Where the port is

The deko3d build boots, plays a match from the entrance to the pinfall, reaches
the celebration and results, saves (including overwriting) and takes system
screenshots. In-ring performance is **50.8–55.4 fps** in the `107` log (draw
3.7 ms, span 19.4 ms, CPU 1963.5 / GPU 998.4 / RAM 2133 MHz) with the measured
profile in [`performance-svr2011.toml`](performance-svr2011.toml).

- Branch `deko3d`.
- Known-good match checkpoint: tag **`deko3d-match-working`** (`b805d26`),
  NRO `13322768BB9EA32EA9D76E2AE11F270D44FD63F8921F1901F24AC607FC1F35B5`.
- Current build (Game_files layout + save fix): `svr2011.nro` 82,774,213 bytes,
  SHA-256 `40BA4887C52DE7B02A43BC84817E039C9E1713EB29060C02F0A59FCC927D8D15`.

## SD layout

```text
SVR2011/
  Game_files/          your own disc files (default.xex, pac/, sound/, movies/,
                       plist360*.arc, nxeart, native_shaders/, pad_icons/,
                       optional Mods/, DLC/, Music/, Custom Movies/)
  svr2011.nro
  svr2011.toml
  Saves/               created by the port
  UserData/            created by the port (cache, crash reports)
  logs/                created by the port
```

The NRO finds `Game_files/` beside itself; without that folder it falls back
to the disc files beside the program (the PC layout). The staging and verifier
scripts (`tools/stage_sd.ps1`, `tools/verify_sd.ps1`) produce and check this
layout.

## Fixed so far

| Issue | Fix | Commit |
|---|---|---|
| Match-start crash (`0xDC` on the replay thread) | `replays=false` drops the recorder callbacks and skips `sub_8217BC90` | `1917a44`, `58dd35b` |
| First in-ring frame crash / recorder stall | recorder update skipped with `replays=false`; 16 MB uam stack | `58dd35b` |
| Capture screenshot froze the console | one reusable present copy list/fence, 3 swapchain images, presents pause out of focus | `a299920` |
| Match stopped at the pinfall | the match end's 8 s fallback forces update side `1` done too | `b805d26` |
| Game data beside the NRO only | `Game_files/` detection and every game-data path moved to `GameRoot()` | current build |
| Flat saves corrupted (read 0 B, next write lost) | `ContentManager` copies the flat save with stdio when hard links/`copy_file` are unavailable on the SD | current build |

## Supported profile

[`performance-svr2011.toml`](performance-svr2011.toml): no FSR,
`native_render_scale=0.5`, `native_scale_effects=true`,
`native_record_thread=true`, 720p, 60 Hz, `replays=false`,
`arena_crowd="off"`.

Instant replays and the arena crowd are **not** part of the supported profile.
The replay recorder costs CPU and was the match-start crash; the crowd costs
GPU. Both are off in the measured settings, and the match/port works without
them.

## Next

1. Clean cut: remove the per-variant shader dump, the 96-line memory-block log
   and the 16 MB stack once the build is stable (keep the functional fixes).
2. Persistent DKSH cache.
3. Vulkan/ImGui overlays (settings, FPS, achievements) on the deko3d path.
4. PGO (not shipped; the instrumented NRO crashes at startup).

## Known limitations

- The folder save `Saves/SaveData.dat/SaveData.Dat` loads and overwriting
  works. Loading a **flat** `Saves/SaveData.dat` can hang on the console;
  convert it to the folder form (move the file into a `SaveData.dat` folder as
  `SaveData.Dat`, delete `Saves/.mount`). Creating a new flat-file save is
  slow/unreliable.
- `dlc_fan_axxess=true` hangs in the fake DLC loader; keep it `false`.
- The stock console was CPU-limited around 33 fps in the earlier build; 60 fps
  is not reachable at stock clocks.
- The Vulkan/ImGui overlays are not drawn on the deko3d path; the game's own UI
  is rendered.
- `arena_crowd="off"` does not replace the stock arena files on the Switch
  (`std::filesystem::copy_file` is `ENOSYS`); the crowd may still render. The
  measured profile keeps it off for the cost.
