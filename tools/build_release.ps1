# Build SVR2011-NX from the user's own extracted game folder.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_release.ps1
#
# With no -GameDir it opens a folder picker. The build runs in WSL2, compiles
# the NRO from the user's default.xex, and stages an SD-card folder. The
# release contains no game code: the NRO is produced locally.
#
# Requirements: Windows 10/11, WSL2 with Ubuntu, devkitPro (the script offers
# to install the system packages), ~10 GB free disk and an internet connection
# for the first build.

[CmdletBinding()]
param(
    [string]$GameDir,
    [string]$OutDir = "",
    [string]$WorkDir = "",
    [string]$Distro = "",
    [string]$DevkitPro = "/opt/devkitpro",
    [int]$Jobs = 4,
    [switch]$Clean,
    [switch]$SkipSetup,
    [switch]$NoStage,
    [switch]$NoOpen,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function BashQuote([string]$Value) {
    # A single-quoted bash word; handles spaces, $, backticks and quotes.
    return "'" + $Value.Replace("'", "'\''") + "'"
}

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

$localAppData = $env:LOCALAPPDATA
if (-not $localAppData) { $localAppData = Join-Path $env:USERPROFILE "AppData\Local" }
if (-not $OutDir) { $OutDir = Join-Path $localAppData "SVR2011-NX\dist" }
if (-not $WorkDir) { $WorkDir = Join-Path $localAppData "SVR2011-NX\work" }

# Refuse a work or output folder that is a drive root or the source tree:
# -Clean removes the work folder.
$workFull = [System.IO.Path]::GetFullPath($WorkDir).TrimEnd('\')
$outFull = [System.IO.Path]::GetFullPath($OutDir).TrimEnd('\')
$workRoot = [System.IO.Path]::GetPathRoot($workFull).TrimEnd('\')
$outRoot = [System.IO.Path]::GetPathRoot($outFull).TrimEnd('\')
if ($workFull -eq $workRoot -or $workFull -eq $repo) {
    Fail "Unsafe -WorkDir: $WorkDir (use a subfolder, not a drive root or the source tree)."
}
if ($outFull -eq $outRoot -or $outFull -eq $repo) {
    Fail "Unsafe -OutDir: $OutDir (use a subfolder, not a drive root or the source tree)."
}

# ---------------------------------------------------------------------------
# 1. The game folder
# ---------------------------------------------------------------------------

if (-not $GameDir) {
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select the extracted WWE SmackDown vs. Raw 2011 folder (the one with default.xex, pac, sound and movies)"
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host "Cancelled."
            exit 0
        }
        $GameDir = $dialog.SelectedPath
    } catch {
        Fail "No game folder given. Pass -GameDir `"<folder>`"."
    }
}

if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) {
    Fail "Game folder not found: $GameDir"
}
$GameDir = (Resolve-Path -LiteralPath $GameDir).Path

$required = @(
    "default.xex",
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
    if (-not (Test-Path -LiteralPath (Join-Path $GameDir $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    Fail ("The game folder is missing: " + ($missing -join ", ") +
          ". Install the game with the PC port's launcher first.")
}

# The file check in the game expects the full disc set. A partial install
# would build but fail on the console, so catch it here.
$counts = @{ "pac" = 265; "sound" = 8; "movies" = 87 }
foreach ($dir in $counts.Keys) {
    $count = (Get-ChildItem -LiteralPath (Join-Path $GameDir $dir) -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($count -lt $counts[$dir]) {
        Fail ("$dir has $count files; the game needs at least $($counts[$dir]). " +
              "Reinstall the game with the PC port's launcher (full install, not a trimmed one).")
    }
}

$xex = Join-Path $GameDir "default.xex"
$expectedXexSize = 15020032
if ((Get-Item -LiteralPath $xex).Length -ne $expectedXexSize) {
    Write-Host ("WARNING: default.xex is {0} bytes; the supported USA/Europe disc's is {1}." -f `
        (Get-Item -LiteralPath $xex).Length, $expectedXexSize) -ForegroundColor Yellow
    Write-Host "         The game will refuse a different version at its file check." -ForegroundColor Yellow
}

Info "Game folder: $GameDir"

# ---------------------------------------------------------------------------
# 2. WSL and paths
# ---------------------------------------------------------------------------

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "WSL2 is required. Install it with: wsl --install -d Ubuntu"
}

$distros = @()
try {
    $distros = & wsl.exe -l -q 2>$null |
        ForEach-Object { $_.Trim([char]0, ' ', "`t", "`r", "`n") } |
        Where-Object { $_ }
} catch { }

if (-not $Distro) {
    foreach ($candidate in @("Ubuntu-26.04", "Ubuntu-24.04", "Ubuntu-22.04", "Ubuntu")) {
        if ($distros -contains $candidate) { $Distro = $candidate; break }
    }
    if (-not $Distro) {
        $Distro = $distros | Where-Object { $_ -notmatch "docker-desktop" } | Select-Object -First 1
    }
}
if (-not $Distro) {
    Fail "No WSL distribution found. Install one with: wsl --install -d Ubuntu"
}
if ($distros -notcontains $Distro) {
    Fail "WSL distribution '$Distro' not found. Available: $($distros -join ', ')"
}

# Make sure it actually starts.
& wsl.exe -d $Distro -- true 2>$null
if ($LASTEXITCODE -ne 0) {
    Fail "WSL distribution '$Distro' did not start."
}

function ToWslPath([string]$Path) {
    # wsl.exe passes backslashes through its own argument layer badly; let
    # bash run wslpath with a single-quoted path instead.
    $command = "wslpath -a -- " + (BashQuote $Path)
    $p = & wsl.exe -d $Distro -- bash -lc $command 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $p) {
        Fail "Could not convert the path for WSL: $Path"
    }
    return ($p | Select-Object -First 1).Trim()
}

Info "WSL distribution: $Distro"

# ---------------------------------------------------------------------------
# 3. Work folder: a private copy of the release source
# ---------------------------------------------------------------------------

if ($Clean -and (Test-Path -LiteralPath $WorkDir)) {
    Info "Cleaning $WorkDir"
    Remove-Item -LiteralPath $WorkDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$src = Join-Path $WorkDir "src"
$sameTree = $false
try {
    $sameTree = ((Resolve-Path -LiteralPath $src -ErrorAction SilentlyContinue).Path -eq $repo)
} catch { }

if (-not $sameTree) {
    Info "Copying the release source to $src"
    $xd = @(
        (Join-Path $repo ".git"),
        (Join-Path $repo "out"),
        (Join-Path $repo "dist"),
        (Join-Path $repo "port\generated"),
        (Join-Path $repo "third_party\nvk"),
        (Join-Path $repo "sdk\thirdparty"),
        (Join-Path $repo "sdk\out")
    )
    $null = robocopy $repo $src /E /XD $xd /XF "default.xex" /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { Fail "Copying the source failed (robocopy exit $LASTEXITCODE)." }

    # sdk/thirdparty is fetched, but these tracked files are the port's
    # changes to it (the marker-aware CMakeLists and the FFmpeg overlay).
    # Without them the fetched tree refuses to configure.
    $trackedThirdparty = @(
        "sdk\thirdparty\CMakeLists.txt",
        "sdk\thirdparty\FFmpeg\config.h",
        "sdk\thirdparty\FFmpeg\config_nfsmw_wmv3.h",
        "sdk\thirdparty\FFmpeg\config_switch_aarch64.h",
        "sdk\thirdparty\FFmpeg\libavcodec\fft_template.c",
        "sdk\thirdparty\FFmpeg\libavcodec\mdct_template.c",
        "sdk\thirdparty\ffmpeg-overlay\.rexglue-fetched",
        "sdk\thirdparty\ffmpeg-overlay\bsf_list.c",
        "sdk\thirdparty\ffmpeg-overlay\codec_list.c",
        "sdk\thirdparty\ffmpeg-overlay\parser_list.c"
    )
    foreach ($rel in $trackedThirdparty) {
        $from = Join-Path $repo $rel
        if (Test-Path -LiteralPath $from) {
            $to = Join-Path $src $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir "portlibs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir "nvk") | Out-Null
$srcWsl = ToWslPath $src
$gameWsl = ToWslPath $GameDir
$portlibsWsl = ToWslPath (Join-Path $WorkDir "portlibs")
$nvkWsl = ToWslPath (Join-Path $WorkDir "nvk")

# Reject paths that would break the generated shell scripts.
foreach ($p in @($srcWsl, $gameWsl, $portlibsWsl, $nvkWsl)) {
    if ($p -match "[`r`n]") { Fail "A path contains a line break; move the game or work folder." }
}

# ---------------------------------------------------------------------------
# 4. Helper shell scripts (avoid quoting the build command by hand)
# ---------------------------------------------------------------------------

function Write-WslScript([string]$Name, [string[]]$Lines) {
    $path = Join-Path $WorkDir $Name
    $text = ($Lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    return (ToWslPath $path)
}

$common = @(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    "cd $(BashQuote $srcWsl)",
    "export DEVKITPRO=$(BashQuote $DevkitPro)",
    "export PORTLIBS_PREFIX=$(BashQuote $portlibsWsl)",
    "export NVK_DIR=$(BashQuote $nvkWsl)",
    "export JOBS=$(BashQuote "$Jobs")"
)

$systemScript = Write-WslScript "setup-system.sh" ($common + @(
    "bash tools/setup_wsl.sh --system"
))
$userScript = Write-WslScript "setup-user.sh" ($common + @(
    "bash tools/setup_wsl.sh --user"
))
$buildScript = Write-WslScript "build.sh" ($common + @(
    "export REXGLUE_SWITCH_NVK_SDK=$(BashQuote ($nvkWsl + "/extracted"))",
    "export SVR2011_XEX=$(BashQuote ($gameWsl + "/default.xex"))",
    "bash tools/build_switch.sh --nro"
))

$log = Join-Path $WorkDir "build.log"
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run:"
    Write-Host "  source    $src"
    Write-Host "  game      $GameDir"
    Write-Host "  source in WSL   $srcWsl"
    Write-Host "  game in WSL     $gameWsl"
    Write-Host "  portlibs in WSL $portlibsWsl"
    Write-Host "  NVK in WSL      $nvkWsl"
    Write-Host "  output    $OutDir"
    Write-Host "  log       $log"
    exit 0
}

function Invoke-Wsl([string]$ScriptWsl, [switch]$Root) {
    $command = "bash " + (BashQuote $ScriptWsl)
    $wslArgs = @("-d", $Distro, "--", "bash", "-c", $command)
    if ($Root) { $wslArgs = @("-u", "root") + $wslArgs }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    # Native stderr (git, cmake, ninja) must be logged, not treated as a
    # terminating PowerShell error.
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & wsl.exe @wslArgs 2>&1 | ForEach-Object {
        $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        Write-Host $line
        [System.IO.File]::AppendAllText($log, "$line`r`n", $utf8)
    }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    return $code
}

# ---------------------------------------------------------------------------
# 5. Setup and build
# ---------------------------------------------------------------------------

if (-not $SkipSetup) {
    Info "Checking the build prerequisites (this may ask for your WSL password once)"
    $code = Invoke-Wsl $systemScript -Root
    if ($code -ne 0) {
        Fail "The system setup failed. See $log (devkitPro install instructions are in docs/BUILDING.md)."
    }
    $code = Invoke-Wsl $userScript
    if ($code -ne 0) { Fail "The user setup failed. See $log." }
}

Info "Building the NRO (first build: 15-40 minutes; later builds are incremental)"
$code = Invoke-Wsl $buildScript
if ($code -ne 0) {
    Fail "The build failed. See $log."
}

$nro = Join-Path $src "out\switch\svr2011.nro"
if (-not (Test-Path -LiteralPath $nro -PathType Leaf)) {
    Fail "The build finished but svr2011.nro was not found at $nro. See $log."
}
Info ("Built {0} ({1:N1} MB)" -f $nro, ((Get-Item -LiteralPath $nro).Length / 1MB))

# ---------------------------------------------------------------------------
# 6. Stage the SD folder
# ---------------------------------------------------------------------------

if ($NoStage) {
    Copy-Item -LiteralPath $nro -Destination (Join-Path $OutDir "svr2011.nro") -Force
    Info "NRO copied to $OutDir (game data not staged)."
} else {
    Info "Staging the SD folder in $OutDir"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "stage_sd.ps1") `
        -GameDir $GameDir -Nro $nro -OutDir $OutDir
    if ($LASTEXITCODE -ne 0) { Fail "Staging the SD folder failed." }

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "verify_sd.ps1") `
        -SdDir $OutDir
    if ($LASTEXITCODE -ne 0) { Fail "The staged SD folder is incomplete." }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "SD folder: $OutDir"
Write-Host "Log:       $log"
Write-Host "Copy the CONTENTS of the SD folder to sdmc:/switch/svr2011/."
Write-Host "Do not upload or share it: it contains your game data."

if (-not $NoOpen) {
    Start-Process explorer.exe $OutDir
}
