# Create the source-only release zip.
#
#   powershell -ExecutionPolicy Bypass -File tools\package_release.ps1
#
# The zip is made from git archive (tracked files only), so generated game
# code, the user's default.xex, NVK, third-party fetches and build outputs are
# absent. The release guard and a zip-content check run first.

[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $repo "port\VERSION.txt") -Raw).Trim()
}
if (-not $Version) { Fail "No version (port\VERSION.txt is empty)." }
$Version = $Version -replace '[^0-9A-Za-z._-]', '-'

if (-not $OutFile) {
    $OutFile = Join-Path $repo "dist\svr2011-nx-$Version.zip"
}
$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

Write-Host "Release guard"
& python (Join-Path $repo "tools\check_no_game_data.py")
if ($LASTEXITCODE -ne 0) { Fail "The release guard failed." }

$dirty = git -C $repo status --porcelain
if ($dirty) {
    Write-Host "WARNING: the working tree has uncommitted changes; git archive uses HEAD." -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
Write-Host "Creating $OutFile from HEAD"
& git -C $repo archive --format=zip --prefix="svr2011-nx-$Version/" --output="$OutFile" HEAD
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutFile)) {
    Fail "git archive failed."
}

# ---------------------------------------------------------------------------
# Verify the zip contents
# ---------------------------------------------------------------------------

Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
$forbiddenExt = @(
    ".iso", ".xex", ".pac", ".bik", ".ymk", ".ymb", ".pck", ".dds",
    ".apk", ".nro", ".nsp", ".xci", ".exe", ".dll", ".so", ".a", ".lib",
    ".obj", ".o", ".pdb", ".elf", ".zip", ".7z", ".rar", ".mp3", ".mp4",
    ".wav", ".flac", ".ogg", ".png", ".jpg", ".jpeg", ".bmp", ".gif",
    ".webp", ".svg", ".ttf", ".otf", ".ico"
)
$forbiddenNames = @(
    "default.xex", "svr2011.exe", "libmain.so", "rexruntime.dll",
    "rexgpu-xenos.dll", "shaders.spv.pak"
)
$forbiddenParts = @(
    "/port/generated/", "/native_shaders/", "/third_party/nvk/",
    "/sdk/out/", "/out/", "/dist/"
)
# sdk/thirdparty is tracked only for the port's 10 overlay files (the
# marker-aware CMakeLists and the FFmpeg configs); the fetched tree is not in
# the zip because git archive only takes tracked files.

$zip = [System.IO.Compression.ZipFile]::OpenRead($OutFile)
$bad = New-Object System.Collections.Generic.List[string]
try {
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        $lower = $name.ToLowerInvariant()
        $leaf = [System.IO.Path]::GetFileName($lower)
        $ext = [System.IO.Path]::GetExtension($lower)
        if ($forbiddenExt -contains $ext) { $bad.Add("forbidden extension: $name") }
        if ($forbiddenNames -contains $leaf) { $bad.Add("forbidden file: $name") }
        foreach ($part in $forbiddenParts) {
            if ($lower.Contains($part)) { $bad.Add("forbidden path '$part': $name") }
        }
        if ($entry.Length -gt 50MB) { $bad.Add("file larger than 50 MB: $name") }
    }
} finally {
    $zip.Dispose()
}

if ($bad.Count -gt 0) {
    Remove-Item -LiteralPath $OutFile -Force
    foreach ($b in $bad) { Write-Host "ERROR: $b" -ForegroundColor Red }
    Fail "The release zip contains forbidden material; deleted."
}

$hash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLower()
$sumFile = "$OutFile.sha256"
"$hash  $([System.IO.Path]::GetFileName($OutFile))" |
    Set-Content -LiteralPath $sumFile -Encoding ASCII

Write-Host ""
Write-Host "Release zip: $OutFile" -ForegroundColor Green
Write-Host "SHA-256:     $hash"
Write-Host "Checksum:    $sumFile"
Write-Host ""
Write-Host "Attach the zip and the .sha256 file to the GitHub release."
Write-Host "Do not attach an NRO, shader pack, game data or the staged SD folder."
