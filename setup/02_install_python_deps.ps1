<#
.SYNOPSIS
    Creates .venv (if it doesn't already exist) and installs the verified
    Python dependency set.

.DESCRIPTION
    Installs from setup/requirements.freeze.txt, NOT the repo-root
    requirements.lock.txt or requirements.txt. Why: this repo has three
    dependency manifests, and only this one matches what was actually
    verified working:
      - requirements.lock.txt pins torch==2.10.0 - wrong; the verified,
        tested environment runs torch==2.8.0+cu128. Do not use this file
        for torch.
      - requirements.txt (267 lines) is a broader, partly-aspirational list
        that includes optional media-processing packages (spacy, librosa,
        webrtcvad, openai-whisper, mediapipe, pyannote.audio) which were
        NEVER installed in the verified working environment - the pipeline
        has documented fallback behavior for all of them (you'll see
        "Optional dependency 'X' could not be imported" WARNING lines in
        client logs; this is expected, not an error). It also has version
        drift on several core packages (numpy, pandas, grpcio, cryptography,
        opencv-python) relative to what's actually installed and verified.
      - setup/requirements.freeze.txt is a straight `pip freeze` of the
        actual, exercised, working venv (56 packages) - this is what this
        script installs.

    torch/torchaudio/torchvision are handled SEPARATELY, before the rest of
    the freeze file, and are NOT installed from it directly: the freeze
    file's pinned versions carry a "+cu128" local version suffix
    (e.g. torch==2.8.0+cu128), which is NOT a real PyPI release - plain
    `pip install torch==2.8.0+cu128` fails on a machine that never had that
    exact wheel built for it. Instead this script:
      1. Detects whether an NVIDIA GPU is present (nvidia-smi on PATH).
      2. Installs torch==2.8.0 / torchaudio==2.8.0 / torchvision==0.23.0
         from the matching official PyTorch wheel index - cu128 if a GPU
         was detected, cpu otherwise - BEFORE anything else.
      3. Installs the rest of the freeze file with the three torch lines
         stripped out, so pip never tries to re-resolve them from PyPI.

    Safe to re-run: skips venv creation if .venv already exists, and pip
    install is idempotent.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (Test-Path ".venv\Scripts\python.exe") {
    Write-Host ".venv already exists - skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Creating .venv with 'python -m venv .venv' ..." -ForegroundColor Cyan
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "venv creation failed. Confirm Python 3.11.x is on PATH (see setup/01_check_prereqs.ps1)." -ForegroundColor Red
        exit 1
    }
}

$PyExe = ".venv\Scripts\python.exe"

Write-Host "Upgrading pip ..." -ForegroundColor Cyan
& $PyExe -m pip install --upgrade pip

# --- Step 1: torch/torchaudio/torchvision, from the matching wheel index ---
$hasGpu = $false
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    try {
        & nvidia-smi | Out-Null
        if ($LASTEXITCODE -eq 0) { $hasGpu = $true }
    } catch { $hasGpu = $false }
}

if ($hasGpu) {
    Write-Host "NVIDIA GPU detected (nvidia-smi) - installing CUDA (cu128) torch build ..." -ForegroundColor Cyan
    $torchIndex = "https://download.pytorch.org/whl/cu128"
} else {
    Write-Host "No NVIDIA GPU detected - installing CPU-only torch build ..." -ForegroundColor Cyan
    Write-Host "(This matches the verified environment's torch/torchaudio/torchvision versions;" -ForegroundColor Cyan
    Write-Host " only the compute backend differs. Training will run on CPU and be slower.)" -ForegroundColor Cyan
    $torchIndex = "https://download.pytorch.org/whl/cpu"
}

& $PyExe -m pip install "torch==2.8.0" "torchaudio==2.8.0" "torchvision==0.23.0" --index-url $torchIndex
if ($LASTEXITCODE -ne 0) {
    Write-Host "torch install failed - see output above." -ForegroundColor Red
    exit 1
}

# --- Step 2: everything else in the freeze file, minus the torch lines ---
$freezePath = "setup\requirements.freeze.txt"
$filtered = Get-Content $freezePath | Where-Object { $_ -notmatch '^(torch|torchaudio|torchvision)==' }
$tmpReq = Join-Path $env:TEMP "requirements.freeze.no-torch.txt"
$filtered | Set-Content -Path $tmpReq -Encoding utf8

Write-Host "Installing the remaining $($filtered.Count) packages from setup/requirements.freeze.txt ..." -ForegroundColor Cyan
& $PyExe -m pip install -r $tmpReq
$installExit = $LASTEXITCODE
Remove-Item $tmpReq -ErrorAction SilentlyContinue

if ($installExit -eq 0) {
    Write-Host ""
    Write-Host "Install complete. Run setup\04_verify.ps1 next." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "pip install reported errors - see output above." -ForegroundColor Red
    exit 1
}
