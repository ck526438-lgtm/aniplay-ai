# Prépare le projet Flutter pour Windows : génère frontend/windows (si absent)
# puis applique l'identité de l'application (nom, icône, taille de fenêtre).
# Idempotent : peut être relancé sans risque.
#
#   .\scripts\prepare_windows.ps1
#   cd frontend ; flutter run -d windows
$ErrorActionPreference = "Stop"
$frontend = Join-Path $PSScriptRoot "..\frontend" | Resolve-Path
Set-Location $frontend

if (-not (Test-Path "windows\runner\main.cpp")) {
    Write-Host "-> Generation du projet Windows (flutter create)"
    flutter create --project-name aniplay --org com.aniplay --platforms=windows .
    if ($LASTEXITCODE -ne 0) { throw "flutter create a echoue" }
}

# flutter create ajoute un test d'exemple qui ne compile pas avec cette application
$sample = "test\widget_test.dart"
if ((Test-Path $sample) -and (Select-String -Path $sample -Pattern "MyApp" -Quiet)) {
    Remove-Item $sample
}

function Edit-File([string]$Path, [scriptblock]$Transform) {
    $text = [IO.File]::ReadAllText((Resolve-Path $Path))
    $new = & $Transform $text
    if ($new -ne $text) {
        # Remplacements 100 % ASCII : on réécrit sans BOM, comme les fichiers générés
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Resolve-Path $Path), $new, $utf8)
        Write-Host "   modifie : $Path"
    }
}

Write-Host "-> Identite de l'application"
Copy-Item "assets\branding\app_icon.ico" "windows\runner\resources\app_icon.ico" -Force

# Titre et taille de la fenêtre au démarrage
Edit-File "windows\runner\main.cpp" {
    param($t)
    $t = $t -replace 'window\.Create\(L"[^"]*"', 'window.Create(L"AniPlay AI"'
    $t -replace 'Win32Window::Size size\(\d+, \d+\)', 'Win32Window::Size size(1280, 760)'
}

# Propriétés du fichier .exe (clic droit > Propriétés > Détails)
Edit-File "windows\runner\Runner.rc" {
    param($t)
    $t = $t -replace '"CompanyName", "[^"]*"', '"CompanyName", "AniPlay AI"'
    $t = $t -replace '"FileDescription", "[^"]*"', '"FileDescription", "AniPlay AI - lecteur d''anime"'
    $t = $t -replace '"ProductName", "[^"]*"', '"ProductName", "AniPlay AI"'
    $t -replace '"LegalCopyright", "[^"]*"', '"LegalCopyright", "Licence MIT - contributeurs AniPlay AI"'
}

Write-Host "OK : projet Windows pret ($frontend\windows)"
