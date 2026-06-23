param (
    [switch]$Offline,
    [int]$Port = 0
)

# 1. Quick sanity check for Docker
$dockerCheck = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Desktop is not running! Please start Docker first."
    Exit
}

# 2. Extract binary name dynamically from Cargo.toml
if (-not (Test-Path "Cargo.toml")) {
    Write-Error "No Cargo.toml found here. Make sure you are in your Rust project root!"
    Exit
}

$cargoContent = Get-Content "Cargo.toml" -Raw
if ($cargoContent -match 'name\s*=\s*"([^"]+)"') {
    $binaryName = $Matches[1]
    Write-Host "Target Binary Detected: $binaryName" -ForegroundColor Yellow
} else {
    Write-Error "Could not read package name from Cargo.toml."
    Exit
}

# 3. Securely handle Build config purely in memory
$dockerfileContent = @"
FROM rust:alpine AS builder
ARG BIN_NAME
WORKDIR /app
COPY . .
RUN cargo test
RUN cargo build --release --target x86_64-unknown-linux-musl

FROM scratch
ARG BIN_NAME
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/`$BIN_NAME /
"@

# 4. Handle Flags
$buildArgs = @()
$runArgs = @()

if ($Offline) {
    Write-Host "[Mode] Strict Offline (Using local cache)..." -ForegroundColor Magenta
    $buildArgs += "--pull=false"
    $runArgs += "--pull=never"
}

$buildArgs += @("--build-arg", "BIN_NAME=$binaryName", "-f", "-", "-o", "./output", ".")

Write-Host "Compiling and extracting static Alpine binary..." -ForegroundColor Cyan
if (Test-Path "output") { Remove-Item "output" -Recurse -Force }

$dockerfileContent | docker build @buildArgs

# 5. Execute runtime engine block
if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[Success] Static binary compiled perfectly!" -ForegroundColor Green
    Write-Host "Booting your application inside Alpine environment..." -ForegroundColor Cyan
    
    $hostOutputDir = (Get-Item .\output).FullName
    $runArgs += @("--rm", "-it")
    
    # Dynamically inject port mapping ONLY if specified by the user
    if ($Port -gt 0) {
        Write-Host "[Network] Exposing inbound port: $Port" -ForegroundColor Gray
        $runArgs += @("-p", "${Port}:${Port}")
    }
    
    $runArgs += @("-v", "${hostOutputDir}:/app", "alpine", "/app/$binaryName")
    docker run @runArgs
} else {
    Write-Error "Build execution failed inside the pipeline container."
}