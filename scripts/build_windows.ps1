# Construit l'application Windows complète d'AniPlay AI :
#   1. backend Python gelé avec PyInstaller (aniplay-backend.exe) + FFmpeg ;
#   2. application Flutter (aniplay.exe) ;
#   3. version portable (.zip) et installateur (.exe, si Inno Setup est installé).
#
# Prérequis : Python 3.11, Flutter 3.27+ (avec « Desktop development with C++ » de Visual Studio),
#             Inno Setup 6 (facultatif, pour l'installateur : winget install JRSoftware.InnoSetup).
#
#   .\scripts\build_windows.ps1                       # édition standard
#   .\scripts\build_windows.ps1 -Edition full         # + sous-titres IA (≈ 350 Mo compressé)
#   .\scripts\build_windows.ps1 -Version 1.2.0 -SkipTests
#
# Résultat dans dist\ :  AniPlay-AI-<version>-<édition>-setup.exe  et  …-portable.zip
param(
    [ValidateSet("standard", "full")] [string]$Edition = "standard",
    [string]$Version = "",
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [string]$Python = "python"
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Invoke-WebRequest est 10x plus lent avec la barre
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$backend = Join-Path $root "backend"
$frontend = Join-Path $root "frontend"
$dist = Join-Path $root "dist"
$cache = Join-Path $root "build-cache"
New-Item -ItemType Directory -Force $dist, $cache | Out-Null

function Step([string]$msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Check([string]$what) { if ($LASTEXITCODE -ne 0) { throw "$what a echoue (code $LASTEXITCODE)" } }

if (-not $Version) {
    $line = Select-String -Path (Join-Path $frontend "pubspec.yaml") -Pattern '^version:\s*([\d.]+)'
    $Version = $line.Matches[0].Groups[1].Value
}
Write-Host "AniPlay AI $Version - edition $Edition"

# ------------------------------------------------------------------ 1. Backend
Step "Backend Python (PyInstaller)"
$venv = Join-Path $backend ".venv-build-$Edition"
if (-not (Test-Path "$venv\Scripts\python.exe")) {
    & $Python -m venv $venv; Check "Creation du venv"
}
$py = "$venv\Scripts\python.exe"
& $py -m pip install --upgrade pip --quiet; Check "pip"
& $py -m pip install -r "$backend\requirements.txt" "pyinstaller>=6.10" --quiet; Check "Dependances backend"
if ($Edition -eq "full") {
    # torch CPU : bien plus léger que la version CUDA (les GPU NVIDIA restent utilisables
    # en installant le backend à la main, voir README)
    & $py -m pip install torch --index-url https://download.pytorch.org/whl/cpu --quiet; Check "torch"
    & $py -m pip install -r "$backend\requirements-subtitles.txt" --quiet; Check "Dependances sous-titres"
}

Push-Location $backend
try {
    $env:ANIPLAY_EDITION = $Edition
    & $py -m PyInstaller packaging\aniplay-backend.spec --noconfirm --clean `
        --distpath "$backend\dist" --workpath "$backend\build"
    Check "PyInstaller"
} finally {
    Pop-Location
}
$backendDist = Join-Path $backend "dist\aniplay-backend"

# ------------------------------------------------------------------ FFmpeg
Step "FFmpeg (build LGPL)"
$ffZip = Join-Path $cache "ffmpeg-lgpl-shared.zip"
if (-not (Test-Path $ffZip)) {
    $url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl-shared.zip"
    Write-Host "Telechargement : $url"
    Invoke-WebRequest $url -OutFile $ffZip
}
$ffTmp = Join-Path $cache "ffmpeg-extract"
if (Test-Path $ffTmp) { Remove-Item -Recurse -Force $ffTmp }
Expand-Archive $ffZip -DestinationPath $ffTmp
$ffBin = Get-ChildItem $ffTmp -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
$ffDest = Join-Path $backendDist "ffmpeg"
New-Item -ItemType Directory -Force $ffDest | Out-Null
# ffmpeg.exe, ffprobe.exe et leurs DLL (pas ffplay)
Get-ChildItem $ffBin.DirectoryName | Where-Object { $_.Name -ne "ffplay.exe" } |
    Copy-Item -Destination $ffDest -Force
$ffLicense = Get-ChildItem $ffTmp -Recurse -Filter "LICENSE*" | Select-Object -First 1
if ($ffLicense) { Copy-Item $ffLicense.FullName (Join-Path $ffDest "LICENSE-ffmpeg.txt") }

# ------------------------------------------------------------------ Auto-test du backend
Step "Auto-test du backend gele"
$testDir = Join-Path $cache "selftest-data"
if (Test-Path $testDir) { Remove-Item -Recurse -Force $testDir }
$p = Start-Process -FilePath (Join-Path $backendDist "aniplay-backend.exe") `
    -ArgumentList "--self-test", "--data-dir", "`"$testDir`"" -Wait -PassThru
$report = Join-Path $testDir "self-test.log"
if (Test-Path $report) { Get-Content $report }
if ($p.ExitCode -ne 0) { throw "Auto-test du backend en echec (code $($p.ExitCode))" }

# Démarrage réel du serveur + /health
$port = 8799
$server = Start-Process -FilePath (Join-Path $backendDist "aniplay-backend.exe") `
    -ArgumentList "--port", "$port", "--data-dir", "`"$testDir`"", "--parent-pid", "$PID" -PassThru
try {
    $ok = $false
    for ($i = 0; $i -lt 120 -and -not $ok; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $health = Invoke-RestMethod "http://127.0.0.1:$port/health" -TimeoutSec 2
            $ok = $health.status -eq "ok"
        } catch { }
        if ($server.HasExited) { break }
    }
    if (-not $ok) {
        $log = Join-Path $testDir "logs\backend.log"
        if (Test-Path $log) { Get-Content $log -Tail 40 }
        throw "Le backend ne repond pas sur /health"
    }
    Write-Host "[ok] /health : $($health | ConvertTo-Json -Compress)"
} finally {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}

# ------------------------------------------------------------------ 2. Flutter
Step "Application Flutter"
& (Join-Path $PSScriptRoot "prepare_windows.ps1")
Push-Location $frontend
try {
    flutter pub get; Check "flutter pub get"
    if (-not $SkipTests) {
        flutter analyze --no-fatal-infos; Check "flutter analyze"
        flutter test; Check "flutter test"
    }
    $buildNumber = if ($env:GITHUB_RUN_NUMBER) { $env:GITHUB_RUN_NUMBER } else { "1" }
    flutter build windows --release --build-name $Version --build-number $buildNumber
    Check "flutter build windows"
} finally {
    Pop-Location
}
$release = Join-Path $frontend "build\windows\x64\runner\Release"
if (-not (Test-Path "$release\aniplay.exe")) { throw "aniplay.exe introuvable dans $release" }

# ------------------------------------------------------------------ Assemblage
Step "Assemblage"
$appBackend = Join-Path $release "backend"
if (Test-Path $appBackend) { Remove-Item -Recurse -Force $appBackend }
Copy-Item -Recurse $backendDist $appBackend
Copy-Item (Join-Path $root "LICENSE") (Join-Path $release "LICENSE.txt") -Force

$base = "AniPlay-AI-$Version-$Edition"
$zip = Join-Path $dist "$base-portable.zip"
if (Test-Path $zip) { Remove-Item $zip }
# Dossier racine dans le zip, pour ne pas éparpiller les fichiers à l'extraction
$staging = Join-Path $cache "portable\AniPlay AI"
if (Test-Path (Split-Path $staging)) { Remove-Item -Recurse -Force (Split-Path $staging) }
New-Item -ItemType Directory -Force $staging | Out-Null
Copy-Item -Recurse "$release\*" $staging
Compress-Archive -Path $staging -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Portable : $zip"

# ------------------------------------------------------------------ 3. Installateur
if (-not $SkipInstaller) {
    Step "Installateur (Inno Setup)"
    $iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
    if (-not $iscc) {
        $iscc = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($iscc) {
        & $iscc "/DAppVersion=$Version" "/DSourceDir=$release" "/DEdition=$Edition" "/DOutputDir=$dist" `
            (Join-Path $root "installer\aniplay.iss")
        Check "Inno Setup"
    } else {
        Write-Warning "Inno Setup introuvable : installateur non genere (winget install JRSoftware.InnoSetup)"
    }
}

Step "Termine"
Get-ChildItem $dist | Format-Table Name, @{ n = "Taille (Mo)"; e = { [math]::Round($_.Length / 1MB, 1) } }
