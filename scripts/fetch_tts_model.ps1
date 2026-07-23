# Downloads a Piper Russian TTS voice for sherpa_onnx and packages it as a single
# zip asset (assets/tts/<voice>.zip) that the app bundles into the APK and unpacks
# to the app support dir on first launch (see lib/tts/tts_service.dart).
# Windows-native: Invoke-WebRequest + built-in tar.exe + .NET ZipFile. No sh.
#
# Usage:
#   pwsh scripts/fetch_tts_model.ps1
#   pwsh scripts/fetch_tts_model.ps1 -Voice vits-piper-ru_RU-denis-medium
#
# Voices: vits-piper-ru_RU-irina-medium (default), -denis-, -dmitri-, -ruslan-medium
param(
    [string]$Voice = 'vits-piper-ru_RU-irina-medium'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root     = Split-Path -Parent $PSScriptRoot
$destDir  = Join-Path $root 'assets/tts'
$voiceDir = Join-Path $destDir $Voice
$archive  = Join-Path $destDir "$Voice.tar.bz2"
$zipPath  = Join-Path $destDir "$Voice.zip"
$url      = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$Voice.tar.bz2"

New-Item -ItemType Directory -Force -Path $destDir | Out-Null

if (-not (Test-Path (Join-Path $voiceDir 'model.onnx'))) {
    Write-Host "Downloading $url ..."
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    Write-Host "Extracting ..."
    & tar.exe -xjf $archive -C $destDir
    if ($LASTEXITCODE -ne 0) { throw "tar extraction failed (exit $LASTEXITCODE)" }
    Remove-Item $archive -Force
    if (-not (Test-Path $voiceDir)) { throw "Expected folder not found: $voiceDir" }

    $modelOnnx = Join-Path $voiceDir 'model.onnx'
    if (-not (Test-Path $modelOnnx)) {
        $onnx = Get-ChildItem -Path $voiceDir -Filter '*.onnx' -File | Select-Object -First 1
        if ($null -eq $onnx) { throw "No .onnx file found inside $voiceDir" }
        Rename-Item -Path $onnx.FullName -NewName 'model.onnx'
        Write-Host "Renamed $($onnx.Name) -> model.onnx"
    }
} else {
    Write-Host "Model folder already present: $voiceDir"
}

Write-Host "Packaging zip asset ..."
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
# includeBaseDirectory = $false -> entries are relative (model.onnx, espeak-ng-data/...) with '/' separators
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $voiceDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

$sizeMb = "{0:N1} MB" -f ((Get-Item $zipPath).Length / 1MB)
Write-Host ""
Write-Host "Ready: $zipPath ($sizeMb)"
Write-Host "It is already declared in pubspec.yaml (flutter/assets). Next:"
Write-Host "  flutter pub get"
Write-Host "  flutter run --flavor komet   (or: flutter build apk --flavor komet)"
Write-Host "The app unpacks it to the support dir on first launch; TTS then works offline."
