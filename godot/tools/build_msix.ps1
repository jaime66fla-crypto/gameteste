# Build a Microsoft Store package (MSIX) of Campo de Fogo.
#
# Usage (from the godot folder):
#   powershell -ExecutionPolicy Bypass -File tools\build_msix.ps1            # package for the Store (unsigned)
#   powershell -ExecutionPolicy Bypass -File tools\build_msix.ps1 -Export    # re-export the Windows build first
#   powershell -ExecutionPolicy Bypass -File tools\build_msix.ps1 -TestSign  # also sign it for a local test install
#
# The identity values come from Partner Center > your app > Product management >
# Product identity. Put them in tools\store_identity.json (see below) so the
# package matches the name reserved in the Store; until then placeholders are used
# and the package can only be installed locally (with -TestSign).
#
# tools\store_identity.json:
#   { "Name": "12345SeuNome.CampodeFogo",
#     "Publisher": "CN=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
#     "PublisherDisplayName": "Seu Nome" }
#
# The Store signs the package itself on submission; do NOT upload a -TestSign build.
param(
    [string]$Godot = "C:\Users\jaime\Desktop\Godot area de criação\Godot_v4.7.2-stable_win64_console.exe",
    [switch]$Export,
    [switch]$TestSign
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 1. Version from project.godot (MSIX wants 4 numbers; the Store needs the last one to be 0).
$match = Select-String -Path project.godot -Pattern '^config/version="([0-9]+\.[0-9]+\.[0-9]+)"'
if (-not $match) { throw "application/config/version ausente em project.godot" }
$version = $match.Matches[0].Groups[1].Value + ".0"
Write-Host "Versão do pacote: $version"

# 2. Identity.
$identity = [pscustomobject]@{
    Name                 = "CampoDeFogo.Local"
    Publisher            = "CN=CampoDeFogoTeste"
    PublisherDisplayName = "Campo de Fogo"
}
$identityFile = Join-Path $PSScriptRoot "store_identity.json"
$storeReady = Test-Path $identityFile
if ($storeReady) {
    $identity = Get-Content $identityFile -Raw | ConvertFrom-Json
} else {
    Write-Warning "tools\store_identity.json não encontrado: usando identidade de teste (não serve para enviar à loja)."
}

# 3. Windows build.
$exe = Join-Path $root "itch\windows\CampoDeFogo.exe"
if ($Export -or -not (Test-Path $exe)) {
    if (-not (Test-Path $Godot)) { throw "Godot não encontrado em $Godot (use -Godot caminho)" }
    New-Item -ItemType Directory -Force (Split-Path $exe) | Out-Null
    & $Godot --headless --path $root --export-release "Windows Desktop" $exe
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw "Export do Godot falhou" }
}

# 4. SDK build tools (makeappx/signtool) from NuGet; no admin or full SDK needed.
$toolsDir = Join-Path $env:LOCALAPPDATA "CampoDeFogo-buildtools"
$makeappx = Get-ChildItem $toolsDir -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1
if (-not $makeappx) {
    Write-Host "Baixando Microsoft.Windows.SDK.BuildTools..."
    New-Item -ItemType Directory -Force $toolsDir | Out-Null
    $zip = Join-Path $toolsDir "buildtools.zip"
    Invoke-WebRequest "https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.BuildTools" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath (Join-Path $toolsDir "pkg") -Force
    Remove-Item $zip
    $makeappx = Get-ChildItem $toolsDir -Recurse -Filter makeappx.exe | Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1
    if (-not $makeappx) { throw "makeappx.exe não encontrado no pacote baixado" }
}
$signtool = Join-Path $makeappx.DirectoryName "signtool.exe"

# 5. Staging folder: exe + logos + manifest.
$storeDir = Join-Path $root "store"
$stage = Join-Path $storeDir "layout"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage "Assets") | Out-Null
# Keep the Godot editor from importing the generated PNGs.
New-Item -ItemType File -Force (Join-Path $storeDir ".gdignore") | Out-Null
Copy-Item $exe $stage

Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Image]::FromFile((Join-Path $root "icon.png"))
function New-Logo([string]$name, [int]$w, [int]$h, [double]$fill = 1.0) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $side = [int]([Math]::Min($w, $h) * $fill)
    $g.DrawImage($icon, [int](($w - $side) / 2), [int](($h - $side) / 2), $side, $side)
    $g.Dispose()
    $bmp.Save((Join-Path $stage "Assets\$name"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
# Base (scale-100) and scale-200 variants of each logo the manifest references.
foreach ($s in @(@{ Suffix = "scale-100"; F = 1 }, @{ Suffix = "scale-200"; F = 2 })) {
    $f = $s.F; $sfx = $s.Suffix
    New-Logo "Square44x44Logo.$sfx.png"   (44 * $f)  (44 * $f)
    New-Logo "Square150x150Logo.$sfx.png" (150 * $f) (150 * $f) 0.8
    New-Logo "Wide310x150Logo.$sfx.png"   (310 * $f) (150 * $f) 0.8
    New-Logo "Square310x310Logo.$sfx.png" (310 * $f) (310 * $f) 0.8
    New-Logo "Square71x71Logo.$sfx.png"   (71 * $f)  (71 * $f)  0.9
    New-Logo "StoreLogo.$sfx.png"         (50 * $f)  (50 * $f)
}
# Taskbar / Start list icons without the tile plate.
foreach ($t in 16, 24, 32, 48, 256) {
    New-Logo "Square44x44Logo.targetsize-$t.png" $t $t
    New-Logo "Square44x44Logo.targetsize-${t}_altform-unplated.png" $t $t
}
$icon.Dispose()

function Escape-Xml([string]$s) { [System.Security.SecurityElement]::Escape($s) }
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">
  <Identity Name="$(Escape-Xml $identity.Name)" Publisher="$(Escape-Xml $identity.Publisher)" Version="$version" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Campo de Fogo</DisplayName>
    <PublisherDisplayName>$(Escape-Xml $identity.PublisherDisplayName)</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Resources>
    <Resource Language="pt-BR" />
  </Resources>
  <Applications>
    <Application Id="CampoDeFogo" Executable="CampoDeFogo.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Campo de Fogo"
        Description="Campo de Fogo - eliminatória online"
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" Square310x310Logo="Assets\Square310x310Logo.png" Square71x71Logo="Assets\Square71x71Logo.png" ShortName="Campo de Fogo">
          <uap:ShowNameOnTiles>
            <uap:ShowOn Tile="square150x150Logo" />
            <uap:ShowOn Tile="wide310x150Logo" />
            <uap:ShowOn Tile="square310x310Logo" />
          </uap:ShowNameOnTiles>
        </uap:DefaultTile>
      </uap:VisualElements>
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClient" />
    <Capability Name="internetClientServer" />
    <Capability Name="privateNetworkClientServer" />
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
[IO.File]::WriteAllText((Join-Path $stage "AppxManifest.xml"), $manifest, (New-Object Text.UTF8Encoding $false))

# 6. Resource index so Windows picks the right logo size (scale-100/200, targetsize-*).
$makepri = Join-Path $makeappx.DirectoryName "makepri.exe"
$priConfig = Join-Path $storeDir "priconfig.xml"
& $makepri createconfig /cf $priConfig /dq pt-BR /pv 10.0.0 /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw "makepri createconfig falhou" }
& $makepri new /pr $stage /cf $priConfig /mn (Join-Path $stage "AppxManifest.xml") /of (Join-Path $stage "resources.pri") /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw "makepri new falhou" }
Remove-Item $priConfig

# 7. Pack.
$suffix = if ($storeReady) { "" } else { "_teste" }
$msix = Join-Path $storeDir "CampoDeFogo_${version}_x64$suffix.msix"
if (Test-Path $msix) { Remove-Item $msix }
& $makeappx.FullName pack /d $stage /p $msix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx falhou" }

# 8. Optional local-test signature (self-signed cert whose subject = Publisher).
if ($TestSign) {
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $identity.Publisher -and $_.HasPrivateKey } | Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -Type Custom -Subject $identity.Publisher -KeyUsage DigitalSignature `
            -FriendlyName "Campo de Fogo (teste local)" -CertStoreLocation Cert:\CurrentUser\My `
            -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
    }
    $cer = Join-Path $storeDir "CampoDeFogo_teste.cer"
    Export-Certificate -Cert $cert -FilePath $cer | Out-Null
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint $msix
    if ($LASTEXITCODE -ne 0) { throw "signtool falhou" }
    Write-Host ""
    Write-Host "Para instalar no seu PC (uma vez, PowerShell como administrador):"
    Write-Host "  Import-Certificate -FilePath '$cer' -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
    Write-Host "Depois dê dois cliques em: $msix"
}

Write-Host ""
Write-Host "Pacote: $msix"
if (-not $storeReady) { Write-Host "Crie tools\store_identity.json com os dados do Partner Center e rode de novo para gerar o pacote da loja." }
