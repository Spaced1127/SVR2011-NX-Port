# Current state

Updated 2026-11-05, after the first full match on hardware.

## Where the port is

The deko3d build boots, plays a match from the entrance to the pinfall, reaches
the celebration and results, saves (including overwriting) and takes system
screenshots. In-ring performance is **50.8–55.4 fps** in the `107` log (draw
3.7 ms, span 19.4 ms, CPU 1963.5 / GPU 998.4 / RAM 2133 MHz), with the measured
profile in [`performance-svr2011.toml`](performance-svr2011.toml).

- Branch `deko3d`.
- Known-good match checkpoint: tag **`deko3d-match-working`** (`b805d26`),
  NRO `13322768BB9EA32EA9D76E2AE11F270D44FD63F8921F1901F24AC607FC1F35B5`.
- Replay/crowd test build: `svr2011.nro` 82,770,117 bytes, SHA-256
  `E7B453277EC3A6E4C39328A09B192CB38760231380E1CA503BB32B6FC62A51DF`
  (adds the recorder startup-buffer clear on top of `b805d26`).

## Fixed so far

| Issue | Fix | Commit |
|---|---|---|
| Match-start crash (`0xDC` on the replay thread) | `replays=false` drops the recorder callbacks and skips `sub_8217BC90` | `1917a44`, `58dd35b` |
| First in-ring frame crash / recorder stall | recorder update skipped with `replays=false`; 16 MB uam stack | `58dd35b` |
| Capture screenshot froze the console | one reusable present copy list/fence, 3 swapchain images, presents pause out of focus | `a299920` |
| Match stopped at the pinfall | the match end's 8 s fallback also forces update side `1` done | `b805d26` |
| Replay test crash (`0xDC` freeing the attract demo's clips) | clear the recorder's 140 clip pointers once at the match start | replay test build |

## Test profiles

Copy one over `svr2011.toml` on the SD card:

- [`performance-svr2011-crowd.toml`](performance-svr2011-crowd.toml) —
  `arena_crowd = "on"`, `replays = false`. The stock arenas keep their audience
  and the crowd's per-frame renderer runs; check that it renders and measure
  the cost.
- [`performance-svr2011-replays.toml`](performance-svr2011-replays.toml) —
  `arena_crowd = "off"`, `replays = true`. The recorder runs and the match-end
  highlights play; check the recording, the highlights and the cost.

The measured profile keeps `replays = false` and `arena_crowd = "off"` for the
51 fps figure.

## Next

1. Crowd: confirm the audience renders with `arena_crowd="on"` and record the
   fps; if the cost is acceptable, decide whether "on" becomes the default.
2. Replays: confirm the match-start `0xDC` is gone, the recording works and the
   match-end highlights play with `replays=true`.
3. Clean cut: remove the per-variant shader dump, the 96-line memory-block log
   and the 16 MB stack once the replay test is stable (keep the functional
   fixes).
4. Remaining features: persistent DKSH cache, Vulkan/ImGui overlays, PGO (not
   shipped).

## Known limitations

- `arena_crowd="off"` relies on the crowd-less arena copies; whether the
  Switch's filesystem places them is still the open question (the stock arena
  is used while a copy is being made).
- `replays=true` is the test path; the measured profile keeps it off because
  the recorder costs CPU (and was the source of the match-start crash).
- The Vulkan/ImGui overlays (settings, FPS, achievements) are not drawn on the
  deko3d path; the game's own UI is rendered.
- `dlc_fan_axxess=true` hangs in the fake DLC loader; keep it `false`.
