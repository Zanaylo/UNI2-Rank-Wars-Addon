[CmdletBinding()]
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$iniPath = Join-Path $root "addon.ini"

function Parse-AddonIni {
    param([string]$Path)
    $meta = [ordered]@{
        id          = "rank-wars"
        name        = "Rank Wars"
        version     = ""
        author      = ""
        description = ""
        url         = ""
    }
    foreach ($raw in (Get-Content -Path $Path -Encoding UTF8)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(";") -or $line.StartsWith("#") -or $line.StartsWith("[")) { continue }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) { continue }
        $k = $line.Substring(0, $eq).Trim().ToLower()
        $v = $line.Substring($eq + 1).Trim()
        if ($meta.Contains($k)) { $meta[$k] = $v }
    }
    return $meta
}

$meta = Parse-AddonIni -Path $iniPath
$rawVersion = if ($Version) { $Version.Trim() } else { $meta.version }
if (-not $rawVersion) { throw "Version not found in $iniPath" }

$cleanVersion = $rawVersion -replace '^[vV]', ''
$tag = "v$cleanVersion"
$folderName = "RankWars"
$zipName = "UNI2-RankWars-$cleanVersion.zip"

$dist = Join-Path $root "dist"
$stage = Join-Path $dist $folderName
$zip = Join-Path $dist $zipName
$manifestPath = Join-Path $dist "addon-manifest.json"

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

$stagedIni = Join-Path $stage "addon.ini"
$iniContent = Get-Content -Path $stagedIni -Raw -Encoding UTF8
$iniUpdated = $iniContent -replace '(?m)^(\s*Version\s*=\s*).*$', "`${1}$cleanVersion"
[IO.File]::WriteAllText($stagedIni, $iniUpdated, (New-Object System.Text.UTF8Encoding $false))

$srcDir = Join-Path $root "src"
if (-not (Test-Path $srcDir)) { throw "Missing required directory: src" }
Copy-Item $srcDir (Join-Path $stage "src") -Recurse -Force

Compress-Archive -Path $stage -DestinationPath $zip -Force
$hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()

$iconSrc = Join-Path $root "icon.png"
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc (Join-Path $dist "icon.png") -Force
}

$manifest = [ordered]@{
    schemaVersion = 1
    id            = $meta.id
    folder        = $folderName
    name          = $meta.name
    version       = $cleanVersion
    tag           = $tag
    author        = $meta.author
    description   = $meta.description
    repo          = $meta.url
    assetName     = $zipName
    sha256        = $hash
}
$manifestJson = $manifest | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding $false))

Write-Host "Packaged Rank Wars add-on $cleanVersion ($tag)"
Write-Host "  -> $zip"
Write-Host "  -> $manifestPath"
Write-Host "  sha256: $hash"
