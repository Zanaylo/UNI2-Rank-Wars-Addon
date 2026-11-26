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

function Build-BundledLua {
    param([string]$RootDir)
    $srcDir = Join-Path $RootDir "src"
    if (-not (Test-Path $srcDir)) { throw "Missing required directory: src" }

    $entryPath = Join-Path $RootDir "main.lua"
    if (-not (Test-Path $entryPath)) { throw "Missing required file: main.lua" }

    $builder = New-Object System.Text.StringBuilder
    $files = Get-ChildItem -Path $srcDir -Recurse -Filter "*.lua" -File | Sort-Object FullName

    foreach ($file in $files) {
        $rel = $file.FullName.Substring($RootDir.Length + 1)
        $moduleName = ($rel -replace '\.lua$', '' -replace '[\\/]', '.')
        $content = (Get-Content -Path $file.FullName -Raw -Encoding UTF8) -replace "\r\n", "`n"
        [void]$builder.Append("package.preload[`"$moduleName`"] = function(...)`n")
        [void]$builder.Append($content.TrimEnd("`n"))
        [void]$builder.Append("`nend`n`n")
    }

    $entryContent = (Get-Content -Path $entryPath -Raw -Encoding UTF8) -replace "\r\n", "`n"
    [void]$builder.Append($entryContent.TrimEnd("`n"))
    [void]$builder.Append("`n")
    return $builder.ToString()
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

$stagedIni = Join-Path $stage "addon.ini"
$iniContent = Get-Content -Path $iniPath -Raw -Encoding UTF8
$iniUpdated = $iniContent -replace '(?m)^(\s*Version\s*=\s*).*$', "`${1}$cleanVersion"
[IO.File]::WriteAllText($stagedIni, $iniUpdated, (New-Object System.Text.UTF8Encoding $false))

$bundledLua = Build-BundledLua -RootDir $root
$stagedMain = Join-Path $stage "main.lua"
[IO.File]::WriteAllText($stagedMain, $bundledLua, (New-Object System.Text.UTF8Encoding $false))

Compress-Archive -Path $stage -DestinationPath $zip -Force
$hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
$size = (Get-Item $zip).Length

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
Write-Host "  -> $zip ($size bytes)"
Write-Host "  -> $manifestPath"
Write-Host "  sha256: $hash"
