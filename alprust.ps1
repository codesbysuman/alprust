param (
    [Parameter(Position=0)]
    [ValidateSet("run", "check", "test", "build")]
    [string]$Action = "run",
    
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

# 3. Process Flags
$buildArgs = @()
$runArgs = @()

if ($Offline) {
    Write-Host "[Mode] Strict Offline (Using local cache)..." -ForegroundColor Magenta
    $buildArgs += "--pull=false"
    $runArgs += "--pull=never"
}

# 4. Route Actions Dynamically
switch ($Action) {
    "check" {
        Write-Host "Running 'cargo check' inside Alpine container context..." -ForegroundColor Cyan
        $dockerfileContent = "FROM rust:alpine`nWORKDIR /app`nCOPY . .`nRUN cargo check"
        $buildArgs += @("--progress=plain", "-f", "-", ".")
        $dockerfileContent | docker build @buildArgs
        Exit
    }
    "test" {
        Write-Host "Running 'cargo test' inside Alpine container context..." -ForegroundColor Cyan
        $dockerfileContent = "FROM rust:alpine`nWORKDIR /app`nCOPY . .`nRUN cargo test"
        $buildArgs += @("--progress=plain", "-f", "-", ".")
        $dockerfileContent | docker build @buildArgs
        Exit
    }
    Default {
        # 'build' or 'run' flows use the multi-stage optimization pipeline
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
        $buildArgs += @("--build-arg", "BIN_NAME=$binaryName", "-f", "-", "-o", "./output", ".")
        Write-Host "Compiling static Alpine binary..." -ForegroundColor Cyan
        if (Test-Path "output") { Remove-Item "output" -Recurse -Force }
        
        $dockerfileContent | docker build @buildArgs
        
        if ($LASTEXITCODE -eq 0 -and $Action -eq "run") {
            Write-Host "`n[Success] Static binary compiled perfectly!" -ForegroundColor Green
            Write-Host "Booting your application inside Alpine environment..." -ForegroundColor Cyan
            
            $hostOutputDir = (Get-Item .\output).FullName
            $runArgs += @("--rm", "-it")
            
            if ($Port -gt 0) {
                Write-Host "[Network] Exposing inbound port: $Port" -ForegroundColor Gray
                $runArgs += @("-p", "${Port}:${Port}")
            }
            
            $runArgs += @("-v", "${hostOutputDir}:/app", "alpine", "/app/$binaryName")
            docker run @runArgs
        } elseif ($LASTEXITCODE -eq 0) {
            Write-Host "`n[Success] Static binary compiled and saved cleanly to ./output/$binaryName" -ForegroundColor Green
        } else {
            Write-Error "Build execution failed inside the pipeline container."
        }
    }
}