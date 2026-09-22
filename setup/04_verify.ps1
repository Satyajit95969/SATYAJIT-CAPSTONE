<#
.SYNOPSIS
    Read-only verification: imports every key package, checks ollama has
    phi3:mini, and prints the paths where the dataset and MentalBERT model
    are expected, with whether they exist yet.

.DESCRIPTION
    Makes no changes. Safe to re-run any number of times, at any point in
    setup - it's meant to be run again after each of steps 6/7/8 in
    setup/README.md to confirm progress.
#>

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "=== Python package import check ===" -ForegroundColor Cyan
if (-not (Test-Path ".venv\Scripts\python.exe")) {
    Write-Host ".venv not found - run setup\02_install_python_deps.ps1 first." -ForegroundColor Red
} else {
    & ".venv\Scripts\python.exe" -c @"
import sys
mods = ['grpc', 'pydantic', 'torch', 'torchaudio', 'torchvision', 'transformers',
        'cryptography', 'pymongo', 'cv2', 'sklearn', 'scipy', 'numpy', 'pandas',
        'pyarrow', 'yaml', 'captum']
failed = []
for m in mods:
    try:
        __import__(m)
    except ImportError as e:
        failed.append((m, str(e)))
if failed:
    print('FAILED IMPORTS:')
    for m, e in failed:
        print(f'  {m}: {e}')
    sys.exit(1)
import torch
print(f'OK - all {len(mods)} key packages import cleanly')
print(f'torch {torch.__version__}  (CUDA build: {torch.version.cuda}; '
      f'cuda available on this machine: {torch.cuda.is_available()})')
"@
}

Write-Host ""
Write-Host "=== Ollama model check ===" -ForegroundColor Cyan
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    $models = & ollama list 2>&1
    Write-Host $models
    if ($models -match "phi3:mini") {
        Write-Host "phi3:mini present." -ForegroundColor Green
    } else {
        Write-Host "phi3:mini NOT found - run: ollama pull phi3:mini" -ForegroundColor Yellow
    }
} else {
    Write-Host "ollama not found on PATH." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Dataset parquet ===" -ForegroundColor Cyan
$parquet = Join-Path $RepoRoot "dataset_build\daic_records_multimodal_participant_only.parquet"
Write-Host "Expected path: $parquet"
if (Test-Path $parquet) {
    $sz = (Get-Item $parquet).Length
    Write-Host "FOUND ($sz bytes)" -ForegroundColor Green
} else {
    Write-Host "NOT FOUND - see setup/README.md section 6." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== MentalBERT model ===" -ForegroundColor Cyan
$modelDir = Join-Path $env:USERPROFILE ".federated\models\mentalbert"
Write-Host "Expected path: $modelDir"
if (Test-Path $modelDir) {
    $hasWeights = (Test-Path (Join-Path $modelDir "pytorch_model.bin")) -or (Test-Path (Join-Path $modelDir "model.safetensors"))
    if ($hasWeights) {
        Write-Host "FOUND (weights present)" -ForegroundColor Green
    } else {
        Write-Host "Directory exists but no pytorch_model.bin / model.safetensors found yet." -ForegroundColor Yellow
    }
} else {
    Write-Host "NOT FOUND - see setup/README.md section 7." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Device enrollment ===" -ForegroundColor Cyan
$clientCert = Join-Path $env:USERPROFILE ".federated\keys\client.pem"
Write-Host "Expected path: $clientCert"
if (Test-Path $clientCert) {
    Write-Host "FOUND - device already enrolled." -ForegroundColor Green
} else {
    Write-Host "NOT FOUND - expected before first enrollment. See setup/README.md section 8." -ForegroundColor Yellow
}
