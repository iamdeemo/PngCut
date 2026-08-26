param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('x86', 'x64')]
    [string]$Architecture
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $root 'PngCut.sln'
$desktopOutput = Join-Path $root ("src\PngCut.Desktop\bin\{0}\Release\net48" -f $Architecture)
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist ("stage-{0}" -f $Architecture)
$zipPath = Join-Path $dist ("PngCut-Windows-{0}.zip" -f $Architecture)
$resourceStage = Join-Path $stage 'Resources'
$engineStage = Join-Path $resourceStage 'engines'

New-Item -ItemType Directory -Path $dist -Force | Out-Null
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null
New-Item -ItemType Directory -Path $engineStage | Out-Null

dotnet build $solution -c Release -p:Platform=$Architecture
if ($LASTEXITCODE -ne 0) { throw "Release build failed for $Architecture." }

if (-not (Test-Path -LiteralPath (Join-Path $desktopOutput 'PngCut.exe'))) {
    throw "Desktop output was not found: $desktopOutput"
}

Get-ChildItem -LiteralPath $desktopOutput -File | Copy-Item -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $desktopOutput 'Resources\licenses') -Destination $resourceStage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $desktopOutput ("Resources\engines\{0}" -f $Architecture)) -Destination $engineStage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination $stage -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "Created $zipPath"
