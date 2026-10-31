# Lance le backend en mode développement (Windows PowerShell)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\backend")

if (-not (Test-Path ".venv")) {
    Write-Host "-> Création de l'environnement virtuel"
    python -m venv .venv
}
& .\.venv\Scripts\Activate.ps1
pip install -q -r requirements-dev.txt
if (-not (Test-Path ".env")) { Copy-Item ".env.example" ".env" }

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
