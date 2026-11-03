# Porting plan

This is the working plan for the Switch port. Each phase has an acceptance
check. The plan is deliberately incremental: get a buildable, legal skeleton
first, then boot the game, then make it playable, then make it fast.

## Current state

The source builds a **66 MB `out/switch/svr2011.nro`** (ARM64, static-pie) with
devkitA64, the Horizon ReXGlue layer, Mesa NVK and the native Vulkan renderer.
The generated game code (403 files) compiles. The NRO has **not been run on
hardware yet**; the next step is the first boot test described in
[TESTING.md](TESTING.md).

## Phase 0 - repository and legal guardrails

- [x] Import the MIT-licensed PC port source (`port/src`, patches, config).
- [x] Import the BSD-3-Clause Horizon ReXGlue layer from NFSMW-NX.
- [x] Import plume (MIT) with the SA2-NX Switch/deko3d work.
- [x] Add `LICENSE`, `THIRD_PARTY_NOTICES.md`, `docs/LEGAL.md`.
- [x] Add `.gitignore` for game data, generated code, builds and shaders.
- [x] Add `tools/check_no_game_data.py`.
- [x] Add a CI check that runs the release guard.

**Acceptance:** `python3 tools/check_no_game_data.py` passes on a clean
checkout; no game data, generated code or shader packs are tracked.

## Phase 1 - host code generator

- [x] Fetch the ReXGlue third-party tree with `tools/fetch_thirdparty.py`.
- [x] Build `rexglue` (host) from `sdk/`.
- [x] Run `rexglue codegen svr2011_manifest.toml` on the user's
      `default.xex`.
- [x] Confirm the generated C++ compiles for Switch (403 generated files).

**Acceptance:** a clean host build produces `sdk/out/linux-amd64/rexglue`,
and codegen from the user's `default.xex` completes without missing symbols.

## Phase 2 - Switch SDK, portlibs and NVK

- [x] Import the Horizon layer (`memory_switch`, `guest_memory_switch`,
      `fiber_switch`, `exception_handler_switch`, `threading_switch`,
      `window_switch`, `surface_switch`, `switch_audio_system`,
      `switch_input_driver`, `rexglue_switch.cmake`).
- [x] Build zlib, expat and zstd for devkitA64.
- [x] Provide Mesa/NVK (`libvulkan.a`) for Horizon (prebuilt for the first
      link; release builds should use mesa-switch).
- [x] Build the full `svr2011.nro` (66 MB) with the game code and native
      Vulkan renderer.
- [ ] Confirm the NRO launches with a title override/forwarder and exits
      cleanly (first hardware test).

**Acceptance:** the NRO runs on hardware, presents through `VK_NN_vi_surface`,
and does not crash on exit.

## Phase 3 - boot the game

- [ ] Apply the SvR port's `rexglue-sdk-svr2011.patch` to the Switch SDK and
      resolve conflicts.
- [ ] Apply the SvR port's `plume-svr2011.patch` to the Switch plume tree.
- [ ] Add a `REXGLUE_PLATFORM_SWITCH` branch to `port/CMakeLists.txt`.
- [ ] Wire the native Vulkan backend to the runtime's Vulkan device and the
      existing `.spv`/`.spvc` shader packs.
- [ ] Add Switch paths (`sdmc:/switch/svr2011`), config defaults and
      dock/undock handling.
- [ ] Boot to the main menu with the user's game data.

**Acceptance:** the game reaches the main menu at 720p with audio and a
controller, without missing-file errors or crashes.

## Phase 4 - playable match

- [ ] Play an exhibition match with entrances.
- [ ] Controller mapping (letter and position layouts).
- [ ] Audio output (audout) and XMA decoding.
- [ ] Saves and settings on the SD card.
- [ ] 30 fps mode (the port already has two world updates per frame).
- [ ] Fix ARM64/endianness/game-specific crashes found on hardware.

**Acceptance:** a 10-minute exhibition match with entrances, audio, saves and
no crash; the 30 fps mode is stable.

## Phase 5 - performance and quality

- [ ] PGO from a console session.
- [ ] LTO, direct calls, hot function ordering, native hot functions.
- [ ] Reduce shadows/effects, textures, crowd and render scale as needed.
- [ ] Measure on Erista and Mariko, docked and handheld.
- [ ] Decide whether deko3d is required for the target frame rate.
- [ ] Add the deko3d backend and shader pipeline only if needed.

**Acceptance:** stable 30 fps in the target scenes at 720p handheld (and
1080p docked if feasible), with no audio/video desync and no memory growth
over a long session.

## Phase 6 - installer and release

- [ ] Installer page or PC-side script that reads the user's ISO/XEX and
      produces the game files, shader pack and NRO locally.
- [ ] Release guard passes; no game data or generated code tracked.
- [ ] GitHub release notes explain the bring-your-own-game model and the
      title-override requirement.
- [ ] Optional: forwarder instructions and a recommended Sphaira setup.
- [ ] Optional: DLC, mods, custom music/movies and online, if they can be
      supported without shipping game material.

**Acceptance:** a new user with a modded Switch, their own game and a PC can
follow the instructions and build/install the port without receiving any
copyrighted material from this project.

## Current known risks

1. **CPU headroom.** The game runs 60 logic updates/s; the Switch has three
   A57 cores at 1.02 GHz. The 30 fps mode saves GPU/present work, not the
   logic updates.
2. **NVK performance.** NVK on Maxwell is usable but has per-draw/per-submit
   costs. Deko3d may be needed for 60 fps.
3. **Patch conflicts.** The PC/Android SDK patch is large and was written
   against a different tree than the Switch SDK fork.
4. **Memory/mapping.** The Switch SDK layer solves most of it, but the guest
   memory window and GPU memory must fit under Horizon's limits.
5. **SD I/O.** Thousands of small files are slow; an asset pack may be
   needed.
6. **Legal.** A distributed NRO with recompiled game code is a derivative
   work; the current release policy is source-only.
