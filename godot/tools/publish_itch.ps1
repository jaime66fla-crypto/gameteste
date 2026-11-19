# Publish Campo de Fogo to itch.io with butler: Windows (PC) and Android (celular)
# always go out together, with the same version.
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
#
# Android: signed with the release keystore kept OUTSIDE the repo, in
#   %APPDATA%\Godot\keystores\campodefogo-release.keystore
#   %APPDATA%\Godot\keystores\campodefogo-release.txt   (alias=..., password=...)
# Back both files up: without them, updates no longer install over the old app.
param(
    [string]$Target = "",            # itch user/game, e.g. "seunome/campo-de-fogo"
    [string]$Channel = "windows",
    [string]$AndroidChannel = "android",
    [string]$Godot = "C:\Users\jaime\Desktop\Godot area de criação\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Butler = "$env:LOCALAPPDATA\itch-butler\butler.exe",
    [string]$Keystore = "$env:APPDATA\Godot\keystores\campodefogo-release.keystore",
    [switch]$SkipAndroid,
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

# 2. Stamp the version into the Windows executable and the Android package
#    (Android versionCode must grow every release: it is the build number).
$presets = [IO.File]::ReadAllText((Join-Path $root "export_presets.cfg"))
$presets = $presets -replace 'application/file_version="[^"]*"', "application/file_version=""$version.0"""
$presets = $presets -replace 'application/product_version="[^"]*"', "application/product_version=""$version.0"""
$presets = $presets -replace '(?m)^version/code=\d+', "version/code=$build"
$presets = $presets -replace '(?m)^version/name="[^"]*"', "version/name=""$version"""
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

# 4. Android (celular): release APK signed with the release keystore.
$apk = $null
if (-not $SkipAndroid) {
    $credFile = [IO.Path]::ChangeExtension($Keystore, ".txt")
    if (-not (Test-Path $Keystore) -or -not (Test-Path $credFile)) { throw "Keystore de release do Android não encontrada: $Keystore" }
    $cred = @{}
    Get-Content $credFile | ForEach-Object { $k, $v = $_ -split "=", 2; if ($v) { $cred[$k.Trim()] = $v.Trim() } }
    # Godot reads the release key from these variables (never written into the repo).
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $Keystore
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $cred["alias"]
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $cred["password"]
    $androidOut = Join-Path $root "itch\android"
    New-Item -ItemType Directory -Force $androidOut | Out-Null
    Get-ChildItem $androidOut -File | Remove-Item
    Write-Host "Exportando versão Android..."
    $process = Start-Process -FilePath $Godot -ArgumentList "--headless", "--path", ".", "--export-release", "Android", "itch/android/CampoDeFogo.apk" -RedirectStandardError $log -RedirectStandardOutput $outLog -PassThru -NoNewWindow -Wait
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    $apk = Join-Path $androidOut "CampoDeFogo.apk"
    if (-not (Test-Path $apk)) { Get-Content $log | Select-Object -Last 20; throw "Exportação Android falhou" }
    Write-Host ("Exportado: {0} ({1:N1} MB)" -f $apk, ((Get-Item $apk).Length / 1MB))
}

if ($DryRun) { Write-Host "DryRun: nada foi enviado."; exit 0 }

# 5. Push. butler only uploads what changed; the itch app patches installs.
& $Butler push $out "$($Target):$Channel" --userversion $version
if ($LASTEXITCODE -ne 0) { throw "butler push falhou" }
if ($apk) {
    & $Butler push $apk "$($Target):$AndroidChannel" --userversion $version
    if ($LASTEXITCODE -ne 0) { throw "butler push (android) falhou" }
}
& $Butler status "$($Target):$Channel"
if ($apk) { & $Butler status "$($Target):$AndroidChannel" }
Write-Host "Publicado $version em https://$(($Target -split '/')[0]).itch.io/$(($Target -split '/')[1])"
