param(
    [switch]$Regenerate
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$generatorPath = Join-Path $PSScriptRoot 'Generate-AppIcon.ps1'
$iconPath = Join-Path $root 'src\PngCut.Desktop\Resources\AppIcon.ico'
if ($Regenerate) {
    & $generatorPath
}

if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "App icon is missing: $iconPath"
}

$bytes = [IO.File]::ReadAllBytes($iconPath)
if ($bytes.Length -lt 6 -or $bytes[2] -ne 1 -or $bytes[3] -ne 0) {
    throw 'App icon is not a valid ICO file.'
}

$count = [BitConverter]::ToUInt16($bytes, 4)
if ($count -lt 4) {
    throw "Expected at least four icon sizes, found $count."
}

$sizes = for ($index = 0; $index -lt $count; $index++) {
    $width = $bytes[6 + ($index * 16)]
    if ($width -eq 0) { 256 } else { [int]$width }
}

foreach ($requiredSize in 32, 64, 128, 256) {
    if ($sizes -notcontains $requiredSize) {
        throw "App icon does not contain a ${requiredSize}x${requiredSize} image."
    }
}

Write-Host "Validated $iconPath with sizes: $($sizes -join ', ')"
