# Check an SD card folder against a staged folder (or the expected layout).
#
#   powershell -ExecutionPolicy Bypass -File tools\verify_sd.ps1 `
#       -SdDir "E:\switch\svr2011" `
#       -StageDir "H:\Projects\svr2011-sd"
#
# Run it after copying and before launching the NRO. It compares file names
# and sizes; it does not read the whole 5 GB (the game checks CRCs itself).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SdDir,

    # The folder produced by tools\stage_sd.ps1. When omitted, only the
    # expected file counts and required files are checked.
    [string]$StageDir
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $SdDir -PathType Container)) {
    Fail "SD folder not found: $SdDir"
}

$expectedCounts = @{
    "pac"   = 265
    "sound" = 8
    "movies" = 87
}
$requiredRoot = @(
    "svr2011.nro",
    "svr2011.toml",
    "default.xex",
    "nxeart",
    "plist360.arc",
    "plist360_4x3.arc",
    "native_shaders\shaders.spv.pak",
    "native_shaders\pipelines.list"
)

$problems = 0

Write-Host "SD folder: $SdDir"
Write-Host ""

foreach ($f in $requiredRoot) {
    $p = Join-Path $SdDir $f
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        Write-Host ("  OK   {0} ({1:N1} MB)" -f $f, ((Get-Item -LiteralPath $p).Length / 1MB))
    } else {
        Write-Host "  MISS $f" -ForegroundColor Red
        $problems++
    }
}

foreach ($dir in $expectedCounts.Keys) {
    $p = Join-Path $SdDir $dir
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        Write-Host "  MISS $dir/ (folder)" -ForegroundColor Red
        $problems++
        continue
    }
    $count = (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($count -ge $expectedCounts[$dir]) {
        Write-Host ("  OK   {0}/ ({1} files)" -f $dir, $count)
    } else {
        Write-Host ("  BAD  {0}/ ({1} files, expected at least {2})" -f $dir, $count, $expectedCounts[$dir]) -ForegroundColor Red
        $problems++
    }
}

if ($StageDir) {
    if (-not (Test-Path -LiteralPath $StageDir -PathType Container)) {
        Fail "staged folder not found: $StageDir"
    }
    Write-Host ""
    Write-Host "Comparing names and sizes with $StageDir ..."
    $stage = Get-ChildItem -LiteralPath $StageDir -Recurse -File
    $sd = @{}
    foreach ($f in Get-ChildItem -LiteralPath $SdDir -Recurse -File -ErrorAction SilentlyContinue) {
        $rel = $f.FullName.Substring((Resolve-Path -LiteralPath $SdDir).Path.Length).TrimStart('\', '/')
        $sd[$rel] = $f.Length
    }
    $missing = 0
    foreach ($f in $stage) {
        $rel = $f.FullName.Substring((Resolve-Path -LiteralPath $StageDir).Path.Length).TrimStart('\', '/')
        if (-not $sd.ContainsKey($rel)) {
            if ($missing -lt 20) { Write-Host "  MISS $rel" -ForegroundColor Red }
            $missing++
        } elseif ($sd[$rel] -ne $f.Length) {
            if ($missing -lt 20) {
                Write-Host ("  SIZE {0}: SD {1} bytes, staged {2} bytes" -f $rel, $sd[$rel], $f.Length) -ForegroundColor Red
            }
            $missing++
        }
    }
    if ($missing -eq 0) {
        Write-Host "  OK   every staged file is on the SD card with the same size."
    } else {
        Write-Host "  $missing file(s) missing or the wrong size (first 20 shown)." -ForegroundColor Red
        $problems++
    }
}

Write-Host ""
if ($problems -eq 0) {
    Write-Host "SD folder looks complete. Launch the NRO with a title override or forwarder." -ForegroundColor Green
    exit 0
}

Write-Host "The copy is incomplete. Re-copy the CONTENTS of the staged folder into $SdDir." -ForegroundColor Yellow
Write-Host "Do not copy the staged folder itself: pac, sound and movies must sit next to svr2011.nro."
exit 1
