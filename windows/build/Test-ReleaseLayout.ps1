param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath
)

$ErrorActionPreference = 'Stop'
$resolvedZip = (Resolve-Path -LiteralPath $ZipPath).Path
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("pngcut-release-" + [guid]::NewGuid().ToString('N'))
$expectedArchitecture = if ($resolvedZip -match 'x86') { 'x86' } elseif ($resolvedZip -match 'x64') { 'x64' } else { $null }

try {
    Expand-Archive -LiteralPath $resolvedZip -DestinationPath $temporaryRoot
    foreach ($required in @('PngCut.exe', 'PngCut.Core.dll', 'PngCut.Engine.dll', 'README.md', 'Resources\licenses', 'Resources\engines')) {
        if (-not (Test-Path -LiteralPath (Join-Path $temporaryRoot $required))) {
            throw "Missing release item: $required"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $temporaryRoot 'setup.exe')) {
        throw 'Portable ZIP must not contain setup.exe.'
    }

    if (-not $expectedArchitecture) {
        throw 'Release ZIP name must include x86 or x64.'
    }

    $engineDirectory = Join-Path $temporaryRoot ("Resources\engines\{0}" -f $expectedArchitecture)
    $engineNames = @(Get-ChildItem -LiteralPath $engineDirectory -File -Filter '*.exe' | Select-Object -ExpandProperty Name | Sort-Object)
    $expectedNames = @('mozjpeg-helper.exe', 'oxipng.exe', 'pngquant.exe')
    if (($engineNames -join ',') -ne ($expectedNames -join ',')) {
        throw "Unexpected engine files: $($engineNames -join ', ')"
    }
    $other = if ($expectedArchitecture -eq 'x86') { 'x64' } else { 'x86' }
    if (Test-Path -LiteralPath (Join-Path $temporaryRoot ("Resources\engines\{0}" -f $other))) {
        throw "Release contains the wrong architecture directory: $other"
    }
    Write-Host "Release layout OK: $resolvedZip"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
