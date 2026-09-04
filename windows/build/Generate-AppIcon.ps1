$ErrorActionPreference = 'Stop'

function Get-BigEndianUInt32([byte[]]$bytes, [int]$offset) {
    return [uint32](([uint64]$bytes[$offset] * 16777216) +
        ([uint64]$bytes[$offset + 1] * 65536) +
        ([uint64]$bytes[$offset + 2] * 256) +
        [uint64]$bytes[$offset + 3])
}

function Test-PngSignature([byte[]]$bytes) {
    return $bytes.Length -ge 24 -and
        $bytes[0] -eq 137 -and $bytes[1] -eq 80 -and $bytes[2] -eq 78 -and $bytes[3] -eq 71 -and
        $bytes[4] -eq 13 -and $bytes[5] -eq 10 -and $bytes[6] -eq 26 -and $bytes[7] -eq 10
}

$root = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $root
$sourceIcon = Join-Path $repositoryRoot 'macos\PngCut\Resources\AppIcon.icns'
$resourceDirectory = Join-Path $root 'src\PngCut.Desktop\Resources'
$iconPath = Join-Path $resourceDirectory 'AppIcon.ico'

if (-not (Test-Path -LiteralPath $sourceIcon)) {
    throw "Source macOS icon is missing: $sourceIcon"
}

$icns = [IO.File]::ReadAllBytes($sourceIcon)
$images = @()
$offset = 8
while ($offset + 8 -le $icns.Length) {
    $chunkLength = [int](Get-BigEndianUInt32 $icns ($offset + 4))
    if ($chunkLength -lt 8 -or $offset + $chunkLength -gt $icns.Length) {
        throw "Invalid ICNS chunk at byte $offset."
    }

    $payload = New-Object byte[] ($chunkLength - 8)
    [Array]::Copy($icns, $offset + 8, $payload, 0, $payload.Length)
    if (Test-PngSignature $payload) {
        $images += [pscustomobject]@{
            Width = [int](Get-BigEndianUInt32 $payload 16)
            Height = [int](Get-BigEndianUInt32 $payload 20)
            Data = $payload
        }
    }

    $offset += $chunkLength
}

$selectedImages = @()
foreach ($size in 32, 64, 128, 256) {
    $image = $images | Where-Object { $_.Width -eq $size -and $_.Height -eq $size } | Select-Object -First 1
    if ($null -eq $image) {
        throw "The macOS icon does not contain a ${size}x${size} PNG image."
    }
    $selectedImages += $image
}

$directoryLength = 6 + (16 * $selectedImages.Count)
$totalLength = $directoryLength + (($selectedImages | Measure-Object -Property { $_.Data.Length } -Sum).Sum)
$ico = New-Object byte[] $totalLength
[Array]::Copy([BitConverter]::GetBytes([uint16]0), 0, $ico, 0, 2)
[Array]::Copy([BitConverter]::GetBytes([uint16]1), 0, $ico, 2, 2)
[Array]::Copy([BitConverter]::GetBytes([uint16]$selectedImages.Count), 0, $ico, 4, 2)

$dataOffset = $directoryLength
for ($index = 0; $index -lt $selectedImages.Count; $index++) {
    $image = $selectedImages[$index]
    $entryOffset = 6 + (16 * $index)
    $ico[$entryOffset] = if ($image.Width -eq 256) { 0 } else { [byte]$image.Width }
    $ico[$entryOffset + 1] = if ($image.Height -eq 256) { 0 } else { [byte]$image.Height }
    [Array]::Copy([BitConverter]::GetBytes([uint16]1), 0, $ico, $entryOffset + 4, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]32), 0, $ico, $entryOffset + 6, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$image.Data.Length), 0, $ico, $entryOffset + 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$dataOffset), 0, $ico, $entryOffset + 12, 4)
    [Array]::Copy($image.Data, 0, $ico, $dataOffset, $image.Data.Length)
    $dataOffset += $image.Data.Length
}

New-Item -ItemType Directory -Path $resourceDirectory -Force | Out-Null
[IO.File]::WriteAllBytes($iconPath, $ico)
Write-Host "Created $iconPath from $sourceIcon"
