param (
    [Parameter(Position=0)]
    [ValidateSet("run", "check", "test", "build", "update", "init")]
    [string]$Action = "run",
    
    [switch]$Offline,
    [switch]$IPv4,
    [int]$Port = 0,

    # Dynamic fallback for arbitrary edge-case Cargo options
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$PassthroughFlags
)

# 1. Handle background self-updates instantly
if ($Action -eq "update") {
    Write-Host "Updating alprust from GitHub..." -ForegroundColor Cyan
    git -C $PSScriptRoot pull
    Exit
}

# 2. Handle project scaffolding
if ($Action -eq "init") {
    Write-Host "--- alprust Scaffold Initializer ---" -ForegroundColor Cyan
    $currentFolder = (Get-Item .).Name
    
    $name = Read-Host "Project Name [Default: $currentFolder]"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $currentFolder }
    
    $version = Read-Host "Version [Default: 0.1.0]"
    if ([string]::IsNullOrWhiteSpace($version)) { $version = "0.1.0" }
    
    $depsInput = Read-Host "Dependencies (e.g., tokio@1.0, serde, axum@0.7)"
    
    $tomlDeps = ""
    if (-not [string]::IsNullOrWhiteSpace($depsInput)) {
        foreach ($dep in ($depsInput -split ',')) {
            $dep = $dep.Trim()
            if ($dep -match '^([^@]+)@(.+)$') {
                $tomlDeps += "    $($Matches[1]) = `"$($Matches[2])`"`n"
            } elseif ($dep -ne "") {
                $tomlDeps += "    $dep = `"*`"`n"
            }
        }
    }

    $cargoToml = @"
[package]
name = "$name"
version = "$version"
edition = "2021"

[dependencies]
$tomlDeps
"@
    $cargoToml | Out-File "Cargo.toml" -Encoding utf8 -Force

    if (-not (Test-Path "src")) { New-Item -ItemType Directory -Path "src" | Out-Null }
    $mainRs = @"
fn main() {
    println!("Hello from alprust scaffolded project: $name!");
}
"@
    $mainRs | Out-File "src/main.rs" -Encoding utf8 -Force

    Write-Host "`n[Success] Rust project '$name' scaffolded cleanly!" -ForegroundColor Green
    Exit
}

# 3. Docker verification sweep
$dockerCheck = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Desktop is not running! Please start Docker first."
    Exit
}

# 4. Dynamic Cargo.toml context parser
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

# 5. Auto-Handle Port Allocation Collisions
if ($Port -gt 0 -and $Action -eq "run") {
    $originalPort = $Port
    while (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue) {
        $Port++
    }
    if ($Port -ne $originalPort) {
        Write-Host "[Warning] Port $originalPort is busy! Auto-shifting to open port: $Port" -ForegroundColor Yellow
    }
}

# 6. Format passthrough flags
$cargoFlagsStr = if ($PassthroughFlags) { $PassthroughFlags -join " " } else { "" }

# 7. Core Arguments Construction
$buildArgs = @()
$runArgs = @()

if ($Offline) {
    Write-Host "[Mode] Strict Offline (Bypassing registry sweeps)..." -ForegroundColor Magenta
    $buildArgs += "--pull=false"
    $runArgs += "--pull=never"
}

if ($IPv4) {
    Write-Host "[Network] Enforcing strict IPv4 fallback network stack..." -ForegroundColor Cyan
    $buildArgs += @("--network", "host")
    $runArgs += @("--sysctl", "net.ipv6.conf.all.disable_ipv6=1")
}

$buildArgs += @("--build-arg", "CARGO_FLAGS=$cargoFlagsStr")

# 8. Execute Subcommand Blocks
switch ($Action) {
    "check" {
        Write-Host "Running 'cargo check' with hot layer registry caches..." -ForegroundColor Cyan
        $dockerfileContent = @"
FROM rust:alpine
WORKDIR /app
COPY . .
ARG CARGO_FLAGS
RUN --mount=type=cache,target=/usr/local/cargo/registry/db \
    --mount=type=cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    cargo check `$CARGO_FLAGS
"@
        $buildArgs += @("--progress=plain", "-f", "-", ".")
        $dockerfileContent | docker build @buildArgs
        Exit
    }
    "test" {
        Write-Host "Running 'cargo test' with hot layer registry caches..." -ForegroundColor Cyan
        $dockerfileContent = @"
FROM rust:alpine
WORKDIR /app
COPY . .
ARG CARGO_FLAGS
RUN --mount=type=cache,target=/usr/local/cargo/registry/db \
    --mount=type=cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    cargo test `$CARGO_FLAGS
"@
        $buildArgs += @("--progress=plain", "-f", "-", ".")
        $dockerfileContent | docker build @buildArgs
        Exit
    }
    Default {
        $dockerfileContent = @"
FROM rust:alpine AS builder
ARG BIN_NAME
ARG CARGO_FLAGS
WORKDIR /app
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry/db \
    --mount=type=cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    cargo test `$CARGO_FLAGS
RUN --mount=type=cache,target=/usr/local/cargo/registry/db \
    --mount=type=cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    cargo build --release --target x86_64-unknown-linux-musl `$CARGO_FLAGS

FROM scratch
ARG BIN_NAME
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/`$BIN_NAME /
"@
        $buildArgs += @("--build-arg", "BIN_NAME=$binaryName", "-f", "-", "-o", "./output", ".")
        Write-Host "Compiling static Alpine binary with cache mounts active..." -ForegroundColor Cyan
        if (Test-Path "output") { Remove-Item "output" -Recurse -Force }
        
        $dockerfileContent | docker build @buildArgs
        
        if ($LASTEXITCODE -eq 0 -and $Action -eq "run") {
            Write-Host "`n[Success] Static binary compiled perfectly!" -ForegroundColor Green
            Write-Host "Booting your application inside Alpine environment..." -ForegroundColor Cyan
            
            $hostOutputDir = (Get-Item .\output).FullName
            
            # --init perfectly registers and intercepts Ctrl+C termination signals
            $runArgs += @("--rm", "-it", "--init")
            
            if ($Port -gt 0) {
                Write-Host "`n[Uniform Network Link Setup Active]" -ForegroundColor Gray
                Write-Host "👉 Host Machine Access URL: http://localhost:$Port" -ForegroundColor Green
                Write-Host "👉 Internal Container URL:  http://0.0.0.0:$Port" -ForegroundColor Yellow
                $runArgs += @("-p", "${Port}:${Port}", "-e", "PORT=$Port")
            }
            
            $runArgs += @("-v", "${hostOutputDir}:/app", "alpine", "/app/$binaryName")
            docker run @runArgs
        } elseif ($LASTEXITCODE -eq 0) {
            Write-Host "`n[Success] Static binary saved cleanly to ./output/$binaryName" -ForegroundColor Green
        } else {
            Write-Error "Build execution failed inside the pipeline container."
        }
    }
}