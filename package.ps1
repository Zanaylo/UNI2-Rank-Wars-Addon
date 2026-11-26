[CmdletBinding()]
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$ini = Join-Path $root "addon.ini"

if (-not $Version) {
    $line = Select-String -Path $ini -Pattern '^\s*Version\s*=\s*(.+)$'
    if (-not $line) { throw "Version not found in $ini" }
    $Version = $line.Matches[0].Groups[1].Value.Trim()
}

$dist = Join-Path $root "dist"
$stage = Join-Path $dist "RankWars"
$zip = Join-Path $dist "UNI2-RankWars-$Version.zip"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

$rootFiles = @(
    "addon.ini",
    "main.lua",
    "README.md"
)

foreach ($file in $rootFiles) {
    $src = Join-Path $root $file
    if (-not (Test-Path $src)) { throw "Missing required file: $file" }
    Copy-Item $src (Join-Path $stage $file) -Force
}

$srcDir = Join-Path $root "src"
if (-not (Test-Path $srcDir)) { throw "Missing required directory: src" }
Copy-Item $srcDir (Join-Path $stage "src") -Recurse -Force

Compress-Archive -Path $stage -DestinationPath $zip -Force
$hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()

Write-Host "Packaged Rank Wars add-on $Version"
Write-Host "  -> $zip"
Write-Host "  sha256: $hash"
