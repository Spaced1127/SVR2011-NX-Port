# Porting an Xbox 360 game to Nintendo Switch with deko3d

Practical notes from the *WWE SmackDown vs. Raw 2011* port (`SVR2011-NX`).
Written for another engineer or agent starting the same kind of port: a
ReXGlue/ReXGlue-SDK Xbox 360 recompilation that wants the Switch's native
`deko3d` GPU API instead of the NVK/Vulkan path.

This is not a deko3d API tutorial. It is the set of decisions, code paths and
failure modes that actually mattered on hardware.

---

## 0. The short version

1. Keep the Vulkan/NVK build as the reference. Bring deko3d up as a second
   backend, selected by `native_backend = "deko3d"`.
2. deko3d is not a drop-in `gpu_backend`. You need:
   - plume's deko3d backend (MIT, from banjo-nx/sa2-nx) and `uam`;
   - a deko3d window/swapchain path that owns the default `NWindow`;
   - a `Backend` implementation for your renderer;
   - a shader path `SPIR-V -> GLSL -> uam -> DKSH`.
3. The biggest wins are removing the Vulkan/NVK per-draw command cost and
   reusing one command list + one fence for the present copy.
4. The biggest traps are the present path (never `dkQueueWaitIdle` per frame),
   synchronous logging on the SD card, and running two world updates in one
   frame while a load is in progress.
5. Do not copy the GPL Renut renderer. Keep your renderer MIT/BSD and use
   plume/uam (MIT/zlib/MPL-2.0).

---

## 1. Architecture

### 1.1 Two renderers

The port has two ways to draw the game:

- **Emulated renderer**: ReXGlue emulates the Xbox 360 Xenos GPU, normally
  presenting through NVK/Vulkan on Switch. This is the reference and the
  fallback.
- **Native renderer**: hook the game's D3D9 device calls, read the game's
  resources/state from guest memory, and draw the same scene with the host
  GPU using the game's own (converted) shaders. On Switch the host API is
  deko3d.

The native renderer is what makes the port playable. It does **not** emulate
Xenos; it stands in for the game's D3D9 runtime. That means game-specific
reverse engineering: D3D object layouts, the device register mirror, the D3D
entry points, and the shader conversion.

The renderer itself draws through **plume**
(`third_party/plume`, a thin RenderDevice/RenderCommandList layer). The
deko3d backend plugs into plume; the renderer code is mostly API-agnostic.

### 1.2 Why deko3d

On SVR2011 the NVK path was draw-bound: about 660 draws and 26 ms of submit
time per frame, ~20 fps in-ring. deko3d removes the Vulkan/NVK command path.
Measured on the same scene:

| Build | Clocks CPU/GPU/RAM | In-ring | Draw | Span |
|---|---|---|---|---|
| NVK (`main`) | 1785 / 921.6 / 1866 MHz | ~20 fps | 8.6 ms | 49.8 ms |
| deko3d | 1963.5 / 998.4 / 1866 MHz | 35 fps | 6.0 ms | 29.0 ms |
| deko3d, replay recorder off | 1963.5 / 998.4 / 2133 MHz | ~51 fps | 3.7 ms | 19.4 ms |
| deko3d, stock clocks | 1020 / 307.2 / 1331.2 MHz | 33 fps | 6.3 ms | 30.2 ms |
| deko3d, `frame_rate=30` | 1963.5 / 998.4 / 1866 MHz | 30 fps | 7.7 ms | 33.3 ms |

Menus run at 60 fps. Heavy entrances (900+ draws) drop to 15-21 fps.
`frame_rate=30` is **worse** than 60 because the game's 30 Hz world step does
twice the work per frame.

### 1.3 What deko3d does not replace

- It does not give you a Vulkan-compatible swapchain. You must create the
  deko3d device/queue/swapchain and own the default `NWindow`.
- It does not compile SPIR-V. You must go through `uam` (GLSL -> DKSH).
- It does not provide a persistent pipeline cache by itself. `uam` caches
  variants in memory; a disk cache is still an open item.
- It does not solve Xbox 360 EDRAM/resolve modeling, texture tiling or
  endianness. Those stay in your renderer.

---

## 2. Build and dependencies

Tested with devkitPro/devkitA64, libnx, deko3d 0.5.0, `uam`, and the
ReXGlue SDK.

```bash
# PC-side SPIRV-Cross (once)
git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Cross
cmake -S SPIRV-Cross -B SPIRV-Cross/build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C SPIRV-Cross/build spirv-cross

# Switch NRO
DEVKITPRO=/opt/devkitpro \
PORTLIBS_PREFIX=/opt/devkitpro/portlibs/switch \
REXGLUE_SWITCH_NVK_SDK=/path/to/nvk/extracted \
bash tools/build_switch.sh --switch
```

The build still links NVK: the emulated renderer/fallback and the SDK's Vulkan
initialization use it. The deko3d **native** path does not draw or present
through Vulkan. At boot you will still see Vulkan device enumeration; then the
app sets:

```cpp
if (native_backend == "deko3d") {
  rex::cvar::SetFlagByName("switch_vulkan_surface", "false");
}
```

so the Vulkan presenter never opens a swapchain on the default `NWindow`.

The NRO is large (80+ MB with the recompiled game). Launch it with a **title
override** (hold R while starting an installed game) or a forwarder with a
**39-bit address space**. Album applet mode does not give the game enough
memory.

---

## 3. The deko3d backend

Files in the SVR2011 port:

| File | Role |
|---|---|
| `port/src/native/gpu.h` | `Backend` interface: create interface, shader format, publish frame, device-lost, pipeline cache |
| `port/src/native/backend_deko3d.cpp` | deko3d device, queue, swapchain, present copy |
| `port/src/native/backend_vulkan.cpp` | reference implementation for the Vulkan path |
| `port/src/native/native_renderer.cpp` | the renderer (plume) |
| `port/src/native/textures.cpp` | guest texture cache/untile/upload |
| `port/src/native/native_hooks.cpp` | D3D entry-point hooks |
| `port/src/native/guest_d3d.h` | game-specific D3D object/register layouts |

### 3.1 Create the interface

```cpp
plume::Deko3DOptions options = plume::Deko3DGetOptions();
options.vulkanY = true;  // the renderer's shaders were built with -fvk-invert-y
plume::Deko3DSetOptions(options);
plume::SetDeko3DLogCallback([](const char* msg) { REXLOG_ERROR("deko3d: {}", msg); });
return plume::CreateDeko3DInterface();
```

`vulkanY` matters: the converted game shaders assume Vulkan's Y direction.
Without it the scene is upside down.

The shader format is `plume::RenderShaderFormat::DEKO3D`, extension `.dk`.
`CompactTables()` returns **false** on deko3d: the renderer uses its big
descriptor tables (2D/3D/cube textures and samplers) as deko3d image/sampler
sets. Shaders address them with bindless handles.

### 3.2 Present path

This is the part that caused the most hardware-specific bugs. The working
shape:

1. The renderer finishes a frame into an RGBA8 image and signals a fence.
2. `PublishFrame(image, width, height, fence)`:
   - create the swapchain lazily from `nwindowGetDefault()`;
   - format `R8G8B8A8_UNORM`, **3 images**;
   - wait for the renderer's fence (the frame is ready);
   - if the applet is not focused, return without presenting;
   - wait for the previous frame's **copy fence**;
   - acquire a swapchain image;
   - copy or blit the frame into it;
   - submit the copy with the copy fence;
   - call `present(index, nullptr, 0)`.
3. The copy fence signs **before** the present. Never wait for the present
   itself on the game thread.

Why 3 images: the screenshot service and the compositor can each hold one
image while the app still needs one to acquire. Two images deadlocked the
render thread during capture.

Why one reused command list and fence: a list created per frame allocates a
1 MB command block and its destructor calls `dkQueueWaitIdle`, which waits for
the present too. When the display is paused (screenshot, focus loss), that
wait never returns and the render thread blocks silently; the logic thread
then waits behind it.

The present code in `backend_deko3d.cpp` is short enough to read as a model:

```cpp
if (fence) queue_->waitForCommandFence(fence);

const bool focused = appletGetFocusState() == AppletFocusState_InFocus;
if (!focused) return;

if (copy_pending_) {
  queue_->waitForCommandFence(copy_fence_.get());
  copy_pending_ = false;
}

uint32_t index = 0;
if (!swapchain_->acquireTexture(nullptr, &index)) return;
plume::RenderTexture* dst = swapchain_->getTexture(index);

copy_list_->begin();
if (swapchain_->getWidth() != width || swapchain_->getHeight() != height) {
  static_cast<plume::Deko3DCommandList*>(copy_list_.get())->blitTexture(dst, image.get());
} else {
  copy_list_->copyTexture(dst, image.get());
}
copy_list_->end();
queue_->executeCommandLists(copy_list_.get(), copy_fence_.get());
copy_pending_ = true;
swapchain_->present(index, nullptr, 0);
```

`blitTexture` is needed when the NWindow's size differs from the renderer's
frame (docked vs handheld, render scale). A plain copy would leave the rest of
the swapchain undefined.

### 3.3 Device loss and pipeline validity

- `DeviceLost()` returns `plume::Deko3DDeviceLost(device)`.
- `PipelineCreated()` returns `pipeline && static_cast<Deko3DGraphicsPipeline*>(pipeline)->valid`.
  A pipeline whose shader failed to compile is not used; the renderer skips
  the draw instead of drawing garbage.
- The deko3d backend's `LoadPipelineCache`/`SavePipelineCache` are **no-ops**.
  Do not point them at the Vulkan/D3D12 cache file.

---

## 4. Shader pipeline

### 4.1 What the renderer needs

The native renderer has the game's shaders converted ahead of time from Xenos
microcode to Vulkan SPIR-V (XenosRecomp). Those shaders are packed as
`shaders.spv.pak` for the Vulkan path. On deko3d they must become DKSH blobs.

The chain:

```text
game shader (Xenos)
  -> XenosRecomp -> SPIR-V
  -> SPIRV-Cross -> Vulkan GLSL
  -> tools/deko3d_glsl.py -> deko3d GLSL (banjo-dk layout)
  -> uam (on the Switch) -> DKSH
```

`tools/deko3d_shaders.py` does the first steps and wraps each shader in the
`BDK3` blob that plume's deko3d backend expects.

### 4.2 Shader pack format

`shaders*.pak` is a simple little-endian archive:

```text
"SVRPAK1\0"         8 bytes
u32                  file count
per file:
  u16                name length
  bytes              name
  u32                offset
  u32                size
then the file bytes
```

The deko3d pack is `shaders.dk.pak` beside `shaders.spv.pak` in
`native_shaders/`. The renderer reads the pack once at startup; loose files
are the development fallback.

Game shader names:

```text
<16-hex-hash>.vs            vertex shader
<16-hex-hash>.ps            pixel shader
<16-hex-hash>.vs.s1         vertex variant 1
<16-hex-hash>.ps.s2         pixel variant 2
<16-hex-hash>.vs.inputs     vertex input semantics
<16-hex-hash>.*.textures    texture slots used
```

### 4.3 Conversion command

```bash
SPIRV_CROSS=/path/to/spirv-cross \
python3 tools/deko3d_shaders.py \
    /path/to/native_shaders \
    /path/to/native_shaders/deko3d
```

It writes `shaders.dk.pak` into the output folder (by default
`native_shaders/deko3d`, then you copy it beside `shaders.spv.pak`).
Conversion result on SVR2011: 926 shaders converted, 0 skipped.

The per-shader conversion uses:

```bash
spirv-cross <shader>.spv --version 460 --vulkan-semantics --relax-nan-checks
```

then `tools/deko3d_glsl.py <vk.glsl> <out.dk> --stage vert|frag`.

### 4.4 The `banjo-dk` binding model

The renderer's game shaders expect:

- a `ByteAddressBuffer g_ConstantBuffer` (set 2, binding 0) with the frame's
  vertex/pixel/shared constants;
- a push-constant block with byte offsets into it;
- two descriptor tables: textures (set 0, binding 0) and samplers
  (set 1, binding 0);
- per-draw texture indices read from the shared constants.

`deko3d_glsl.py` rewrites that to:

- `g_ConstantBuffer` -> storage buffer binding 0;
- the push block -> a `std140` UBO at binding 5;
- every texture/sampler pair -> `layout(binding = K) uniform sampler2D dk_tex_bK;`
- a metadata line:

```glsl
// banjo-dk ubo=0x... ssbo=0x... tex=1 texb=K:texByteOffset:sampByteOffset,...
```

The deko3d backend parses `texb=` and binds the texture/sampler per draw from
the bytes in the shared constants. `ownb=` is the same for the renderer's own
constants (present, FSR, debug shaders).

The converter is deliberately conservative: unsupported constructs are
reported and the shader is skipped, never guessed at. If your renderer uses a
different constant/table layout, adapt this script rather than hand-editing
hundreds of shaders.

### 4.5 uam quirks

- uam's GLSL frontend wants Mesa's `gl_VertexID` / `gl_InstanceID`, not
  Vulkan's `gl_VertexIndex` / `gl_InstanceIndex`. The converter rewrites them.
- uam does not know some SPIRV-Cross extensions; the converter drops
  `GL_EXT_nonuniform_qualifier`, `GL_EXT_samplerless_texture_functions`,
  `GL_EXT_spirv_intrinsics`, `GL_EXT_scalar_block_layout`.
- Compile errors go to the app log through the plume callback. A failed
  pipeline is skipped, which looks like a missing draw, not a crash.
- The first use of a shader compiles it on the console. Expect a stutter at
  the first entrance/scene. Prebuild known pipelines in the menus
  (`native_prepare_pipelines`) to move that cost.
- The SVR2011 build uses a 16 MB uam stack. Keep that until your shaders
  compile cleanly; a too-small stack shows up as a uam failure or a crash in
  the compiler.

### 4.6 The BDK3 blob

Each `.dk` file in the pack is:

```text
u32 magic = 0x334B4442 ("BDK3")
u32 stage = 0 (vertex) / 4 (fragment)
u32 glsl_size
u32 reserved = 0
bytes glsl
```

plume's deko3d backend feeds the GLSL to uam and caches the resulting DKSH
variant in memory. A persistent DKSH cache on disk is **not implemented** in
this port.

---

## 5. Native renderer integration

This part is game-specific. The reusable lesson is the shape, not the addresses.

### 5.1 Hook the game's D3D entry points

`native_hooks.cpp` hooks the game's D3D9 functions, calls the original first
(so the emulated renderer still works in shadow mode), then hands the call to
the native renderer. The minimum set:

- `DrawIndexedVertices`
- `DrawVerticesUP` + `EndVertices` (2D/HUD quads)
- `SetRenderTarget`
- `Clear`
- `Resolve`
- `CreateVertexShader` / `CreatePixelShader`
- `SetTexture`, `SetStreamSource`, `SetIndices`, `SetVertexDeclaration`
- `Present` (usually in a separate frame-stats hook)

The original call must run first when the emulated renderer is also active;
the hook then reads the arguments from a saved `PPCContext` because the call
clobbers the argument registers.

### 5.2 Find the game's D3D object layouts

`guest_d3d.h` is the result of a **D3D census build**: hooks on every D3D
function, capture the objects, dump their layouts, and correlate the device's
register mirror with the GPU register groups. For another game you must redo
this:

- find the guest address of the D3D device (constant for the session);
- identify the resource header and the per-type layouts (texture, vertex
  buffer, index buffer, surface, shaders, vertex declaration);
- identify the device's register mirror groups (fetch constants, ALU
  constants, boolean constants, RB/VGT state, viewport, depth bias);
- identify the D3D function addresses (the port keeps a `d3d_map.csv`).

Do not assume SVR2011's offsets. The Xbox 360 D3D runtime is shared, but the
game's own objects and the device pointer are not.

### 5.3 Frame lifecycle

```text
guest D3D calls
  -> hooks record the call/state
  -> native renderer records draws into plume command lists
  -> renderer submits, signals a frame fence
  -> backend PublishFrame(image, fence)
  -> present copy to swapchain
  -> swapchain present
```

The renderer's `OnPresent(front_buffer)` is where a frame is finished. The
backend's `PublishFrame` may run on the render thread; it must not block the
logic thread. The SVR2011 present path only waits for the renderer's fence and
the previous copy fence, never for the display.

### 5.4 Textures

`textures.cpp` is the other large reusable piece:

- Guest textures are described by Xenos fetch constants (6 dwords).
- Each distinct texture is uploaded once: detile, endian-swap, convert
  unsupported formats, upload to a host texture.
- Mip layout and packed mip tails follow the SDK's Xenia texture utilities.
- Textures are re-checked against guest memory periodically because streamed
  textures reuse memory.
- The texture tables are the renderer's descriptor sets:
  - 2D, 3D, cube textures in one image set (deko3d contiguous ranges);
  - samplers in a second set.
- `deko3d` supports BC/DXT; if the host GPU cannot sample BC, decode on the CPU
  to RGBA8/RG8/R8 before upload.
- 16-bit UNORM textures that cannot be linearly filtered are converted to
  16-bit float on the CPU.
- Resolve targets are registered in the texture cache: a fetch of the resolved
  address samples the render target copy, not guest memory. `swap_rb` and gamma
  view formats are tracked because the game's swizzles depend on them.

Texture format mapping is the most common source of "wrong colours" or
"missing texture" bugs. Log the Xenos fetch format, the chosen host format and
the component mapping once per distinct texture; include the unsupported-format
counter in the performance log.

### 5.5 Render targets and resolves

The Xbox 360 renders into EDRAM surfaces. The native renderer stands in with
host render targets:

- color/depth targets sized to the scene (render scale, widescreen);
- `OnResolve` copies the target into a texture the game samples;
- `native_resolve_write_back` copies one-off render-to-texture results back to
  guest memory when the game reads them (attire baking, etc.).

A resolve into a null texture must be skipped, not dereferenced. The D3D code
will happily read a null destination's fields; a ported arena caused an
intermittent crash exactly there.

### 5.6 Constants and pipelines

The game writes constants into the device mirror; the renderer tracks dirty
ranges and uploads them into a big ByteAddressBuffer. Per-draw blocks are read
straight from memory. The shader sees the same `g_ConstantBuffer`.

The pipeline key includes:

```text
vs, ps, vs_variant, ps_variant, topology, render target format,
depth, blend, colour mask, cull, stencil ref/mask, layout hash,
polygon offset scale/offset
```

Pipelines are created on first use and cached in memory. On Vulkan/D3D12 the
port also writes a pipeline cache file; on deko3d that is currently a no-op.
Prebuild the known pipeline list in the menus to avoid first-use stutter.

### 5.7 Vertex decode

The game uses Xbox 360 vertex formats, including the packed `8in32` layout.
`native_renderer.cpp` converts vertices on the CPU/NEON where the host format
differs. Keep the conversion in one place and key it by the vertex declaration;
a wrong stride/offset shows as exploded geometry, not a crash.

---

## 6. Switch platform integration

### 6.1 Window and presenter

- The deko3d backend owns `nwindowGetDefault()` and its swapchain.
- `switch_vulkan_surface = false` prevents the Vulkan presenter from creating a
  second swapchain on the same window.
- The app's Vulkan/ImGui overlays are **not** drawn on the deko3d path in this
  port. The game's own UI is rendered by the native renderer. If you need
  overlays, port them through plume/deko3d.
- Pause presenting when the applet loses focus:
  `appletGetFocusState() != AppletFocusState_InFocus`. Queueing another frame
  while the display is paused blocks in the window's buffer queue and can
  freeze the logic thread.
- Use 3 swapchain images so a screenshot/compositor can hold images without
  starving the app.

### 6.2 Memory

- The guest has 512 MB of Xbox 360 RAM; the port maps it plus caches. The
  process limit is about 3.2 GB, so a title override/39-bit address space is
  required.
- The emulated GPU's shared memory may be a full 512 MB host-visible Vulkan
  buffer; do not assume it is free.
- Guest memory and host GPU memory are unified on Switch. Texture/buffer
  allocations still cost, so keep a cache and retire objects after the frame.
- Avoid per-frame command-list/buffer allocation. The present path's per-frame
  list was both a leak and a deadlock.

### 6.3 Filesystem and saves

The Switch SD card is not a normal POSIX filesystem for `std::filesystem`:

- `std::filesystem::copy_file` returns `ENOSYS`.
- Hard links are unavailable.
- A flat save (`Saves/SaveData.dat`) can mount as 0 bytes or corrupt the next
  write. Use the folder form (`Saves/SaveData.dat/SaveData.Dat`) where possible.
- The port's `ContentManager` falls back to binary `stdio` copy when hard links
  and `copy_file` fail. If you copy saves or game data, implement the same
  fallback; do not assume `copy_file` works.
- Keep `Saves/`, `UserData/`, `logs/` beside the NRO, not inside `Game_files/`.
- `Game_files/` is optional: if it exists beside the NRO, it is the game root;
  otherwise the NRO's folder is. Always resolve game data through one
  `GameRoot()` helper.

### 6.4 Logging can freeze the game (important)

This is the least obvious Switch-specific failure.

- The SDK logger is synchronous by default on PC. Warnings/errors flush to the
  SD card **from the thread that logs**. If the SD write stalls, that thread
  blocks. If it is the render/ring thread, the game freezes.
- A frozen game can look like a game bug while the app log simply stopped
  earlier. In the SVR2011 `117` run the app log stopped at 02:31:53, but the
  separate profiler log kept writing until about 02:33:40: the game was still
  running for those two minutes, and the freeze came later. That rules out the
  last app-log line as the freeze point.
- On Switch the port now defaults `log_async = true` with
  `async_overflow_policy::overrun_oldest`: the game thread only enqueues, and a
  stalled SD write drops the oldest lines instead of blocking. The spdlog pool
  thread sets its Horizon priority to **0x3B**, the only priority Horizon
  time-slices (0x2B audio, 0x2C presentation, 0x2D ring are not time-sliced).
- Queue size is `log_async_cola` (8192 by default). The log line
  `log: async writer on, overrun oldest (queue 8192)` confirms the path.
- Keep a separate profiler log if you can. If the app log stops but the
  profiler continues, suspect logging/SD, not the game. If both stop, suspect
  the process or the card.

### 6.5 Thread priorities

Observed Horizon priorities in this port:

| Thread | Priority |
|---|---|
| Audio | 0x2B |
| Presentation / VSync | 0x2C |
| Game ring / render | 0x2D |
| Time-sliced work (logger, etc.) | 0x3B |

Only 0x3B is time-sliced. A helper thread created from a 0x2C/0x2D thread
inherits a priority that may never run when the console is busy. Set helper
priorities explicitly.

### 6.6 Logging, screenshots, focus

- The system screenshot service can hold swapchain images. 3 images and the
  copy-fence present path fixed the in-ring capture freeze.
- When the applet is not focused (HOME, sleep), do not present. The app can
  keep rendering, but queueing presents blocks.
- `appletGetFocusState()` is the reliable check.

---

## 7. Diagnostics

### 7.1 Logs

The app writes sequential logs (`svr2011_*.log`), a profiler log
(`rex_perfil.log`), a crash log (`rex_crash.log`) and stderr. On SVR2011 they
live under `logs/` and `logs/rex/`.

- `svr2011_*.log`: the app's own log. The last line is **not necessarily** the
  freeze point if the logger stalled.
- `rex_perfil.log`: 10-second performance samples in Spanish, thread CPU,
  memory, audio, libnx stats. If it continues after the app log stops, the
  logger/SD is the problem.
- `rex_crash.log`: cumulative. It may contain old unrelated sections
  (`C:\Windows\Fonts\...` from PC runs). Look at the **last** `====` section.
- `rex_stderr.log`: SaltyNX/NVK warnings; a clean file does not mean no crash.

### 7.2 Crash vs hang vs logger stall

- **Guest fault**: `rex_crash.log` gets a `fallo de acceso a memoria` section
  with `pc`, `lr`, `far`, ESR and registers. `far dentro de la memoria del
  invitado: 0x...` means the fault address was a guest address (often a null
  pointer plus an offset).
- **Hang**: the app log stops, the game still shows a frame, the profiler may
  continue; no crash section. Watchdogs may dump guest threads.
- **Logger stall**: app log stops but profiler/other logs continue; the game
  freezes later when a game thread logs. Fix the logger, not the game.
- **Whole-process stall**: both app and profiler logs stop. Suspect the SD
  card, a native deadlock, or a crash handler that could not write.

### 7.3 Mapping `imagen+0x...` to source

The unstripped `out/switch/svr2011.elf` is the symbol source:

```bash
/opt/devkitpro/devkitA64/bin/aarch64-none-elf-addr2line \
  -e out/switch/svr2011.elf -f -C 0x918a60
```

`imagen+0x...` is the module-relative host address. It maps to generated
recompiled C++ (`port/generated/default/svr2011_recomp.*.cpp`) or SDK code.
For the generated code, the line number points at the guest instruction's
translation; read the surrounding comments to see the guest register/offset.

The crash report's stack walk is not always reliable after a fault; trust `pc`,
`lr`, the instruction word, `far`, and the registers more than the frame chain.

### 7.4 Watchdogs used in this port

- `frame rate: no frame for 10 s - guest thread dump`
- `frame rate: no world update for 10 s - guest thread dump`
- per-pass `world update stuck N s` with job events
- 60 s stuck pass: exit to the Home menu
- 300 s no world update: exit

The 10 s dump prints guest thread PCs. If you see no dump at all, the watchdog
thread is blocked too (usually the logger/SD).

### 7.5 Common log lines worth grepping

```text
deko3d: swapchain ... 
deko3d: uam: variant N a shader (stage ..., ... key ...)
deko3d: uam: run-time variant ...
native renderer: pipeline ... 
native renderer: texture not supported: format ...
native renderer: resolve flags ...
native renderer: dynamic texture ...
native renderer: shader pack ... (N files, ... KB)
frame rate: no frame for 10 s
frame rate: no world update for 10 s
```

A `uam: variant` line means a shader variant is being compiled; a burst is a
first-use stutter. A `texture not supported` line means the texture cache chose
the placeholder; look at the format mapping.

---

## 8. Performance

### 8.1 The working profile

`docs/performance-svr2011.toml`:

```toml
native_renderer = "main"
native_backend = "deko3d"
native_render_scale = 0.5
native_upscale = "off"
native_scale_effects = true
native_record_thread = true
frame_rate = 60
replays = false
arena_crowd = "off"
```

Measured 50.8-55.4 fps in-ring (draw 3.7 ms, span 19.4 ms) on the overclocked
console. FSR 1 quality 4/5 was ~25 fps: EASU/RCAS cost more than the smaller
scene saved on this GPU. Do not enable FSR on deko3d without measuring.

### 8.2 Knobs that matter

| Knob | Effect |
|---|---|
| `native_render_scale` | scene pixels; 0.5 is a big win on Switch |
| `native_scale_effects` | shadows/reflections/glow at render scale |
| `native_texture_quality` | skip big mip levels (memory/upload) |
| `native_record_thread` | record commands off the render thread; helps weak CPUs |
| `native_prepare_pipelines` | prebuild known pipelines in menus |
| `native_upscale` | off / fsr1 / fsr2; FSR1 measured slower on this GPU |
| `frame_rate` | 60 is faster than 30 here |

### 8.3 What did not help

- `-O3` for the generated game code: no measurable change.
- PGO: the instrumented NRO crashes at startup on Horizon (libgcov); not
  shipped.
- FSR 1 on this GPU: slower than the resolution saving.
- A per-frame present command list: allocation + `dkQueueWaitIdle`; worse and
  deadlock-prone.

### 8.4 Shader/present costs

- The renderer's shaders are compiled by uam on first use. A scene with many
  new variants stutters; prebuild them.
- Present is a full-frame copy/blit. At 720p it is small compared with the
  scene, but do not add a CPU wait.
- The renderer's draw/submit split is visible in `native perf` logs. `draw` is
  CPU recording; `gpu wait` is the previous frame; `submit` is the API call.

---

## 9. Porting checklist for another game

### Phase 0 - baseline

- Get the ReXGlue/NVK build booting and playing. Keep it as the reference.
- Add the `deko3d` branch/option without breaking NVK.
- Confirm title override/forwarder memory, input, audio, and save paths.

### Phase 1 - deko3d bring-up

- Import plume's deko3d backend + uam; build with `PLUME_DEKO3D=ON`.
- Write a minimal deko3d test: clear the NWindow swapchain and present a
  colored frame. No game, no shaders.
- Implement `Backend::CreateInterface`, `SetDevice`, `PublishFrame`,
  `PipelineCreated`, `DeviceLost`.
- Disable the Vulkan presenter when `native_backend=deko3d`.
- Acceptance: a stable 60 Hz colored frame, no NVK swapchain.

### Phase 2 - shaders

- Build the SPIR-V pack for the game.
- Convert with `deko3d_shaders.py`; fix `deko3d_glsl.py` for the game's binding
  model.
- Convert the **present** shader first, then 2D/menu shaders, then one scene
  shader.
- Acceptance: menu and practice ring draw with correct colors/textures.

### Phase 3 - scene

- Hook the D3D entry points and build the game's object/register layouts
  (census).
- Implement draw decoding, constants, render targets, resolves and the texture
  cache.
- Add the pipeline key and first-use cache.
- Acceptance: a full match, entrance to pinfall, no missing draws.

### Phase 4 - platform

- Save/load on Switch (folder save, stdio fallback).
- Logging: async non-blocking, helper priorities.
- Applet focus, screenshots, docked/handheld resize.
- Title override/Game_files layout.

### Phase 5 - hardening

- Long soak, repeated scene transitions, screenshots in-ring, HOME/sleep.
- Watchdogs: no-frame/no-world dumps; exit instead of freezing forever.
- Document known limitations and unsupported settings.

---

## 10. Pitfalls and do-nots

- **Do not** create a command list per present frame. Reuse one list and one
  fence.
- **Do not** call `dkQueueWaitIdle` on the game/render thread. It waits for the
  display and deadlocks with screenshots/focus loss.
- **Do not** use 2 swapchain images if screenshots matter. Use 3.
- **Do not** present while the applet is not focused.
- **Do not** assume `std::filesystem::copy_file` or hard links work on the SD.
- **Do not** log synchronously from the ring thread on Switch; a stalled SD
  write freezes the game.
- **Do not** run two world updates in one frame while a load is in progress.
  The game's load jobs are built for one update per 60 Hz frame; a queued
  callback run twice can crash or deadlock. SVR2011's replay recorder read
  guest `0xDC` exactly this way; the model/match load hung the same way.
- **Do not** trust the last app log line as the freeze point. Check the
  profiler log and timestamps.
- **Do not** assume a missing crash report means no crash; a host-side stall
  or logger block writes nothing.
- **Do not** copy Renut (GPL-3.0). Keep your renderer MIT/BSD and use
  plume/uam.
- **Do not** commit game data, `default.xex`, generated game C++, shader packs
  or NROs. Run the release guard.

---

## 11. Legal and repository hygiene

- The port is MIT/BSD. plume's deko3d backend is MIT. uam is
  zlib/MIT/MPL-2.0. SPIRV-Cross is Apache-2.0.
- The Renut renderer used by some sa2-nx versions is GPL-3.0. Do not copy it
  or link it into an MIT/BSD port.
- Keep the game's data, recompiled game code and converted shader packs out of
  the repository. They are derivative works of the user's game.
- A release contains source and build tools only. The user supplies their own
  disc data and builds the NRO.
- Run `python3 tools/check_no_game_data.py` before every push.

---

## 12. File map / references

SVR2011-specific paths; adapt names to your port.

| Path | What to read |
|---|---|
| `docs/DEKO3D.md` | the long design/measurement log for this backend |
| `docs/STATE.md` | current working state and fixes |
| `docs/TESTING.md` | first-hardware-test checklist |
| `docs/BUILDING.md` | toolchain, NVK, codegen, NRO, SD staging |
| `port/src/native/gpu.h` | backend interface |
| `port/src/native/backend_deko3d.cpp` | deko3d device/present |
| `port/src/native/backend_vulkan.cpp` | Vulkan reference backend |
| `port/src/native/native_renderer.cpp` | renderer, pipelines, constants |
| `port/src/native/textures.cpp` | texture cache/untile/upload |
| `port/src/native/native_hooks.cpp` | D3D hooks |
| `port/src/native/guest_d3d.h` | game D3D object/register layouts |
| `tools/deko3d_shaders.py` | SPIR-V pack -> deko3d GLSL pack |
| `tools/deko3d_glsl.py` | Vulkan GLSL -> `banjo-dk` GLSL |
| `tools/pack_shaders.py` | shader pack format |
| `sdk/src/core/logging.cpp` | Switch async logger/priority |
| `sdk/src/ui/` | window/presenter integration |

External references:

- `ChanseyIsTheBest/sa2-nx`: `docs/deko3d-renderer-guide.md`,
  `docs/porting-guide.md`, `app/thirdparty/plume` (deko3d backend), uam.
- `StevensND/nfsmw-nx`: the NVK Switch layer this port started from.
- banjo-nx: plume deko3d backend and shader passes.
- devkitPro: deko3d (zlib), uam (zlib/MIT/MPL-2.0).
- KhronosGroup/SPIRV-Cross (Apache-2.0).

---

## Appendix A - shader pack format (exact)

```text
offset 0:  "SVRPAK1\0" (8 bytes)
offset 8:  u32 count (little-endian)
offset 12: directory entries:
             u16 name_length
             name bytes (UTF-8, no NUL)
             u32 file_offset
             u32 file_size
then:      file bytes
```

`deko3d_shaders.py` writes `shaders.dk.pak` with the same format; each `.dk`
entry is a `BDK3` blob.

## Appendix B - present path checklist

```text
[ ] swapchain format R8G8B8A8_UNORM
[ ] 3 images
[ ] one reused copy command list
[ ] one reused copy fence
[ ] wait for renderer frame fence before copy
[ ] wait for previous copy fence before reusing the list
[ ] copy if same size, blit if different
[ ] submit copy with the copy fence
[ ] present(index, nullptr, 0)
[ ] pause on applet focus loss
[ ] resize the swapchain when the window changes
```

## Appendix C - useful settings

```toml
native_renderer = "main"
native_backend = "deko3d"
native_render_scale = 0.5
native_upscale = "off"
native_scale_effects = true
native_record_thread = true
native_prepare_pipelines = true
frame_rate = 60
full_speed = true
replays = false
```

On Switch, `log_async = true` and `log_async_cola = 8192` are the defaults in
this port. If you need to debug a logger stall, keep them; the game is more
important than the last line.

## Appendix D - a minimal deko3d frame

```cpp
// once
NWindow* win = nwindowGetDefault();
plume::RenderSwapChainDesc desc(win, plume::RenderFormat::R8G8B8A8_UNORM, 3);
auto swap = queue->createSwapChain(desc);
auto list = queue->createCommandList();
auto fence = device->createCommandFence();

// each frame, after the renderer signals render_fence
queue->waitForCommandFence(render_fence);
if (appletGetFocusState() != AppletFocusState_InFocus) return;
if (pending) { queue->waitForCommandFence(fence.get()); pending = false; }
uint32_t index = 0;
if (!swap->acquireTexture(nullptr, &index)) return;
auto* dst = swap->getTexture(index);
list->begin();
list->copyTexture(dst, image);   // blitTexture if sizes differ
list->end();
queue->executeCommandLists(list.get(), fence.get());
pending = true;
swap->present(index, nullptr, 0);
```

---

*These notes are from the SVR2011-NX `deko3d` branch. They are not a
specification; verify every address, format and priority on your own game and
firmware. Keep the NVK reference build until the deko3d path is proven on
hardware.*
