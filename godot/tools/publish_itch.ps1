# Publish the Windows build of Campo de Fogo to itch.io with butler.
#
# Usage (from the godot folder):
#   powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1
#   powershell -ExecutionPolicy Bypass -File tools\publish_itch.ps1 -DryRun   # export only
#
# Release checklist:
#   1. Bump application/config/version in project.godot (e.g. 0.1.0 -> 0.2.0).
#   2. Run this script. Players using the itch.io app get the update automatically.
#   3. If the new build changes how the game talks to the server, raise
#      GODOT_MIN_BUILD in ../wrangler.jsonc (0.2.0 = 200) and deploy the Worker:
#      older builds are then told to update instead of joining matches.
param(
    [string]$Target = "",            # itch user/game, e.g. "seunome/campo-de-fogo"
    [string]$Channel = "windows",
    [string]$Godot = "C:\Users\jaime\Desktop\Godot area de criação\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Butler = "$env:LOCALAPPDATA\itch-butler\butler.exe",
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$configFile = Join-Path $root "tools\itch_target.txt"
if (-not $Target -and (Test-Path $configFile)) { $Target = (Get-Content $configFile -Raw).Trim() }
if (-not $DryRun -and -not $Target) { throw "Informe -Target seunome/jogo ou grave-o em tools\itch_target.txt" }

# 1. Version from project.godot.
$match = Select-String -Path project.godot -Pattern '^config/version="([0-9]+\.[0-9]+\.[0-9]+)"'
if (-not $match) { throw "application/config/version ausente em project.godot" }
$version = $match.Matches[0].Groups[1].Value
$parts = $version.Split(".") | ForEach-Object { [int]$_ }
$build = $parts[0] * 10000 + $parts[1] * 100 + $parts[2]
Write-Host "Versão $version (build $build)"

# 2. Stamp the version into the Windows executable metadata.
$presets = [IO.File]::ReadAllText((Join-Path $root "export_presets.cfg"))
$presets = $presets -replace 'application/file_version="[^"]*"', "application/file_version=""$version.0"""
$presets = $presets -replace 'application/product_version="[^"]*"', "application/product_version=""$version.0"""
[IO.File]::WriteAllText((Join-Path $root "export_presets.cfg"), $presets, (New-Object Text.UTF8Encoding $false))

# 3. Clean export.
$out = Join-Path $root "itch\windows"
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -File | Remove-Item
$log = Join-Path $env:TEMP "campo-de-fogo-export.log"
$outLog = Join-Path $env:TEMP "campo-de-fogo-export-out.log"
Write-Host "Exportando versão Windows..."
$process = Start-Process -FilePath $Godot -ArgumentList "--headless", "--path", ".", "--export-release", "`"Windows Desktop`"", "itch/windows/CampoDeFogo.exe" -RedirectStandardError $log -RedirectStandardOutput $outLog -PassThru -NoNewWindow -Wait
$exe = Join-Path $out "CampoDeFogo.exe"
if (-not (Test-Path $exe)) { Get-Content $log | Select-Object -Last 20; throw "Exportação falhou" }
Write-Host ("Exportado: {0} ({1:N1} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))

if ($DryRun) { Write-Host "DryRun: nada foi enviado."; exit 0 }

# 4. Push. butler only uploads what changed; the itch app patches installs.
& $Butler push $out "$($Target):$Channel" --userversion $version
if ($LASTEXITCODE -ne 0) { throw "butler push falhou" }
& $Butler status "$($Target):$Channel"
Write-Host "Publicado $version em https://$(($Target -split '/')[0]).itch.io/$(($Target -split '/')[1])"
