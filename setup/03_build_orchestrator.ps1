<#
.SYNOPSIS
    Builds the Rust orchestrator in release mode.

.DESCRIPTION
    Runs `cargo build --release` in server/orchestration_agent. protoc is
    NOT required - tonic-build/prost-build (Cargo.toml-pinned versions)
    bundle their own; verified by a real build with no protoc on PATH.

    Safe to re-run: cargo build is incremental and will not redo work that
    is already up to date.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OrchDir = Join-Path $RepoRoot "server\orchestration_agent"

if (-not (Test-Path $OrchDir)) {
    Write-Host "Expected directory not found: $OrchDir" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "cargo not found on PATH. Install Rust via https://rustup.rs first." -ForegroundColor Red
    exit 1
}

Set-Location $OrchDir
Write-Host "Building orchestrator (cargo build --release) in $OrchDir ..." -ForegroundColor Cyan
cargo build --release

if ($LASTEXITCODE -eq 0) {
    $exe = Join-Path $OrchDir "target\release\orchestrator.exe"
    Write-Host ""
    Write-Host "Build succeeded: $exe" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "cargo build failed - see output above." -ForegroundColor Red
    exit 1
}
