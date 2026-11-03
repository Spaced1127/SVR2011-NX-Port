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

    [string]$Nro = (Join-Path $PSScriptRoot "..\out\switch\svr2011.nro"),

    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) "svr2011-sd"),

    # Only print what would be copied.
    [switch]$DryRun,

    # Copy Mods/DLC/Music/Custom Movies when the PC install has them.
    [switch]$IncludeOptional
)

$ErrorActionPreference = "Stop"

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
if ($outFull.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    Fail "OutDir must be outside the repository ($repo); got $outFull"
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
# Written by tools/stage_sd.ps1 for the first hardware test.
gpu_plugin = "xenos"
native_renderer = "main"
gpu_backend = "vulkan"
input_backend = "switch"
resolution = "720p"
resolution_scale = 1
fullscreen = true
vsync = true
'@

$copies = @(
    @{ From = $Nro; To = "svr2011.nro"; Kind = "file" },
    @{ From = (Join-Path $GameDir "default.xex"); To = "default.xex"; Kind = "file" },
    @{ From = (Join-Path $GameDir "nxeart"); To = "nxeart"; Kind = "file" },
    @{ From = (Join-Path $GameDir "plist360.arc"); To = "plist360.arc"; Kind = "file" },
    @{ From = (Join-Path $GameDir "plist360_4x3.arc"); To = "plist360_4x3.arc"; Kind = "file" },
    @{ From = (Join-Path $GameDir "pac"); To = "pac"; Kind = "dir" },
    @{ From = (Join-Path $GameDir "sound"); To = "sound"; Kind = "dir" },
    @{ From = (Join-Path $GameDir "movies"); To = "movies"; Kind = "dir" },
    @{ From = (Join-Path $GameDir "native_shaders"); To = "native_shaders"; Kind = "dir" }
)

if (Test-Path -LiteralPath (Join-Path $GameDir "pad_icons")) {
    $copies += @{ From = (Join-Path $GameDir "pad_icons"); To = "pad_icons"; Kind = "dir" }
}
if ($IncludeOptional) {
    foreach ($name in @("Mods", "DLC", "Music", "Custom Movies")) {
        $src = Join-Path $GameDir $name
        if (Test-Path -LiteralPath $src) {
            $copies += @{ From = $src; To = $name; Kind = "dir" }
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
Write-Host "Copy the CONTENTS of that folder to sdmc:/switch/svr2011/ on the SD card."
Write-Host "Do not upload or share the folder: it contains game data."
