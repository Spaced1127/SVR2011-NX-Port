# Assemble the SD card folder for a first hardware test.
#
#   powershell -ExecutionPolicy Bypass -File tools\stage_sd.ps1 `
#       -GameDir "H:\Projects\SVR2011" `
#       -Nro "out\switch\svr2011.nro" `
#       -OutDir "H:\Projects\svr2011-sd"
#
# This copies YOUR OWN game data. The output folder must never be uploaded,
# zipped for release or committed: it contains the game and its shaders.
# The default OutDir is outside this repository.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir,

    [string]$Nro = "",

    [string]$OutDir = "",

    # Only print what would be copied.
    [switch]$DryRun,

    # Copy Mods/DLC/Music/Custom Movies when the PC install has them.
    [switch]$IncludeOptional
)

$ErrorActionPreference = "Stop"

# Resolved here, not in the param defaults: $PSScriptRoot is not always set
# when Windows PowerShell evaluates them with a relative -File path.
if (-not $Nro) { $Nro = Join-Path $PSScriptRoot "..\out\switch\svr2011.nro" }
if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) "svr2011-sd"
}

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) {
    Fail "Game folder not found: $GameDir"
}
if (-not (Test-Path -LiteralPath $Nro -PathType Leaf)) {
    Fail "NRO not found: $Nro (build it with tools\build_switch.sh --switch)"
}

$GameDir = (Resolve-Path -LiteralPath $GameDir).Path
$Nro = (Resolve-Path -LiteralPath $Nro).Path
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

# Refuse to stage game data inside the source repository: the release guard
# would not catch an untracked folder, and it is too easy to commit by accident.
$outFull = [System.IO.Path]::GetFullPath($OutDir)
$repoPrefix = $repo.TrimEnd('\') + '\'
$outRoot = [System.IO.Path]::GetPathRoot($outFull).TrimEnd('\')
if ($outFull.TrimEnd('\') -eq $repo -or
    $outFull.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    Fail "OutDir must be outside the repository ($repo); got $outFull"
}
if ($outFull.TrimEnd('\') -eq $outRoot) {
    Fail "OutDir must be a folder, not a drive root: $outFull"
}

$required = @(
    "default.xex",
    "nxeart",
    "plist360.arc",
    "plist360_4x3.arc",
    "pac",
    "sound",
    "movies",
    "native_shaders\shaders.spv.pak",
    "native_shaders\pipelines.list"
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir $rel))) {
        $missing += $rel
    }
}
if ($missing.Count -gt 0) {
    Fail ("The game folder is missing: " + ($missing -join ", ") +
          ". Install the game with the PC port's launcher first.")
}

# The Switch defaults. Keep the PC settings out: input_backend=xinput is not
# valid on the console and would leave the pad dead.
$toml = @'
# WWE SmackDown vs. Raw 2011 - Nintendo Switch settings.
# Written by tools/stage_sd.ps1. The SD layout:
#   SVR2011/Game_files/   your own disc files (default.xex, pac, sound, ...)
#   SVR2011/svr2011.nro
#   SVR2011/svr2011.toml
# Tune the GPU block for your console.
gpu_plugin = "xenos"
native_renderer = "main"
gpu_backend = "vulkan"
input_backend = "switch"
resolution = "720p"
resolution_scale = 1
fullscreen = true
vsync = true
# The measured deko3d profile: a half-resolution scene with the effects
# scaled with it, no FSR, the crowd and shadows off, command recording on its
# own thread. Measured ~51 fps in-ring on the overclocked console.
native_max_scale = 1
native_2x_msaa = false
native_prepare_pipelines = true
native_texture_quality = "low"
native_scale_effects = true
native_render_scale = 0.5
native_upscale = "off"
native_record_thread = true
native_shadows = false
arena_crowd = "off"
depth_of_field = false
motion_blur = false
# 0 leaves the clocks to sys-clk (the measured console runs 1963.5 / 998.4 /
# 2133 MHz). 460 is the official handheld GPU profile without an overclock.
switch_gpu_mhz = 0
# true: face buttons by position (Switch bottom = Xbox A), as on an Xbox pad.
# false: by letter (Switch A = Xbox A).
input_xbox_layout = true
# The port's fake Fan Axxess package is incomplete and hangs the DLC loader;
# leave it off. unlock_everything is off for the same reason.
unlock_everything = false
dlc_fan_axxess = false
# Instant replays / match-end highlights are off in the measured profile: the
# recorder costs CPU and was the match-start crash. A match still ends without
# the replay.
replays = false
svr2011_watchdog_dump = true
# Save reads: a folder save (Saves/SaveData.dat/SaveData.Dat) loads without a
# copy; the flat-file form is still slow on the console.
nfsmw_io_ventana_kb = 1024
nfsmw_io_ventanas_max = 32
nfsmw_io_cache_mb = 64
nfsmw_io_rangos_mb = 32
# Skip the render-to-texture write-back/watch that caused 134k emulated
# reads/s during the match load.
native_resolve_write_back = false
'@

$copies = @(
    @{ From = $Nro; To = "svr2011.nro"; Kind = "file" },
    @{ From = (Join-Path $GameDir "default.xex"); To = "Game_files\default.xex"; Kind = "file" },
    @{ From = (Join-Path $GameDir "nxeart"); To = "Game_files\nxeart"; Kind = "file" },
    @{ From = (Join-Path $GameDir "plist360.arc"); To = "Game_files\plist360.arc"; Kind = "file" },
    @{ From = (Join-Path $GameDir "plist360_4x3.arc"); To = "Game_files\plist360_4x3.arc"; Kind = "file" },
    @{ From = (Join-Path $GameDir "pac"); To = "Game_files\pac"; Kind = "dir" },
    @{ From = (Join-Path $GameDir "sound"); To = "Game_files\sound"; Kind = "dir" },
    @{ From = (Join-Path $GameDir "movies"); To = "Game_files\movies"; Kind = "dir" },
    @{ From = (Join-Path $GameDir "native_shaders"); To = "Game_files\native_shaders"; Kind = "dir" }
)

if (Test-Path -LiteralPath (Join-Path $GameDir "pad_icons")) {
    $copies += @{ From = (Join-Path $GameDir "pad_icons"); To = "Game_files\pad_icons"; Kind = "dir" }
}
if ($IncludeOptional) {
    foreach ($name in @("Mods", "DLC", "Music", "Custom Movies")) {
        $src = Join-Path $GameDir $name
        if (Test-Path -LiteralPath $src) {
            $copies += @{ From = $src; To = "Game_files\$name"; Kind = "dir" }
        }
    }
}

function Get-SizeMB($Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        $bytes = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object Length -Sum).Sum
    } else {
        $bytes = $item.Length
    }
    if (-not $bytes) { return 0 }
    return [math]::Round($bytes / 1MB, 1)
}

Write-Host "Game folder: $GameDir"
Write-Host "NRO:         $Nro"
Write-Host "Output:      $outFull"
Write-Host ""

$total = 0
foreach ($c in $copies) {
    $mb = Get-SizeMB $c.From
    $total += $mb
    Write-Host ("  {0,8:N1} MB  {1}" -f $mb, $c.To)
}
Write-Host ("  {0,8:N1} MB  svr2011.toml (written)" -f 0.0)
Write-Host ("  {0,8:N1} MB  total" -f $total)
Write-Host ""

if ($DryRun) {
    Write-Host "Dry run: nothing copied."
    exit 0
}

New-Item -ItemType Directory -Force -Path $outFull | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $outFull "Game_files") | Out-Null
foreach ($c in $copies) {
    $dst = Join-Path $outFull $c.To
    if ($c.Kind -eq "dir") {
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        # robocopy is much faster than Copy-Item for the thousands of game files.
        $null = robocopy $c.From $dst /E /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { Fail "robocopy failed for $($c.To) (exit $LASTEXITCODE)" }
    } else {
        Copy-Item -LiteralPath $c.From -Destination $dst -Force
    }
}
[System.IO.File]::WriteAllText((Join-Path $outFull "svr2011.toml"), $toml, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Done: $outFull"
Write-Host "Copy the CONTENTS of that folder to sdmc:/switch/SVR2011/ on the SD card:"
Write-Host "  Game_files/  svr2011.nro  svr2011.toml"
Write-Host "Do not upload or share the folder: it contains game data."
