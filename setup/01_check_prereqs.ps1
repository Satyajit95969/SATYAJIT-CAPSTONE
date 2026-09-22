<#
.SYNOPSIS
    Read-only check for this project's prerequisites. Prints what is present
    and what is missing. Makes no changes to the system.

.DESCRIPTION
    Checks, in the order setup/README.md documents them:
      - Python 3.11.x on PATH
      - Git for Windows (specifically needed for openssl.exe in mingw64\bin,
        used to verify the enrollment client certificate)
      - Rust toolchain (cargo / rustc)
      - MongoDB Server 8.0 binary
      - Ollama
      - ffmpeg (used by the capture pipeline; optional for a pure
        training/aggregation workflow, but the LDA layer expects it)
      - protoc: informational only. tonic-build/prost-build (pinned in
        server/orchestration_agent/Cargo.toml) bundle their own protoc, so
        `cargo build --release` does NOT require protoc on PATH - verified
        by a real build with no protoc installed. Only relevant if you ever
        need to regenerate the .proto-derived Python/Rust stubs by hand.

    Safe to re-run any number of times.
#>

$ErrorActionPreference = 'Continue'
$results = @()

function Test-Cmd($name, $cmd, $versionArgs) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        try {
            $ver = & $cmd $versionArgs 2>&1 | Select-Object -First 1
        } catch {
            $ver = "(found, version check failed)"
        }
        $global:LASTEXITCODE = 0
        return [PSCustomObject]@{ Name = $name; Status = "OK"; Detail = "$($found.Source) -- $ver" }
    } else {
        return [PSCustomObject]@{ Name = $name; Status = "MISSING"; Detail = "" }
    }
}

Write-Host "=== Prerequisite check (read-only) ===" -ForegroundColor Cyan

# Python
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    $pyver = & python --version 2>&1
    if ($pyver -match '3\.11\.') {
        $results += [PSCustomObject]@{ Name = "Python 3.11.x"; Status = "OK"; Detail = "$($py.Source) -- $pyver" }
    } else {
        $results += [PSCustomObject]@{ Name = "Python 3.11.x"; Status = "WRONG VERSION"; Detail = "$($py.Source) -- $pyver (this project's venv was built with 3.11.9)" }
    }
} else {
    $results += [PSCustomObject]@{ Name = "Python 3.11.x"; Status = "MISSING"; Detail = "" }
}

# Git for Windows (need mingw64\bin\openssl.exe specifically)
$gitOpenssl = "C:\Program Files\Git\mingw64\bin\openssl.exe"
if (Test-Path $gitOpenssl) {
    $results += [PSCustomObject]@{ Name = "Git for Windows (openssl.exe)"; Status = "OK"; Detail = $gitOpenssl }
} else {
    $results += [PSCustomObject]@{ Name = "Git for Windows (openssl.exe)"; Status = "MISSING"; Detail = "expected at $gitOpenssl" }
}

# Rust
$results += Test-Cmd "Rust (cargo)" "cargo" "--version"
$results += Test-Cmd "Rust (rustc)" "rustc" "--version"

# MongoDB
$mongod = "C:\Program Files\MongoDB\Server\8.0\bin\mongod.exe"
if (Test-Path $mongod) {
    $results += [PSCustomObject]@{ Name = "MongoDB Server 8.0"; Status = "OK"; Detail = $mongod }
} else {
    $results += [PSCustomObject]@{ Name = "MongoDB Server 8.0"; Status = "MISSING"; Detail = "expected at $mongod" }
}

# Ollama
$results += Test-Cmd "Ollama" "ollama" "--version"

# ffmpeg
$results += Test-Cmd "ffmpeg" "ffmpeg" "-version"

# protoc (informational only, see synopsis)
$protoc = Get-Command protoc -ErrorAction SilentlyContinue
if ($protoc) {
    $results += [PSCustomObject]@{ Name = "protoc (optional)"; Status = "OK"; Detail = $protoc.Source }
} else {
    $results += [PSCustomObject]@{ Name = "protoc (optional)"; Status = "not found (not required - see synopsis)"; Detail = "" }
}

$results | Format-Table -AutoSize

$missing = $results | Where-Object { $_.Status -eq "MISSING" -or $_.Status -eq "WRONG VERSION" }
if ($missing) {
    Write-Host ""
    Write-Host "Missing/incorrect: $($missing.Name -join ', ')" -ForegroundColor Yellow
    Write-Host "See setup/README.md section 1 for install links." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All required prerequisites present." -ForegroundColor Green
}
exit 0
