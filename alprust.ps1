param (
    [Parameter(Position=0)]
    [ValidateSet("run", "check", "test", "build", "update", "init", "help")]
    [string]$Action = "run",
    
    [switch]$Offline,
    [switch]$IPv4,
    [switch]$Refresh,
    [int]$Port = 0,

    # Dynamic fallback for arbitrary edge-case Cargo options
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$PassthroughFlags
)

function Show-Header ($Message, $Color = "Cyan") {
    Write-Host "`n[alprust] $Message" -ForegroundColor $Color
}

if ($Action -eq "help") {
    Write-Host @"

=======================================================================
   alprust CLI 🚀 - Ultra-lean Alpine Linux Compilation Suite
=======================================================================
Created and maintained by codesbysuman.

Usage:
  alprust [subcommand] [flags] [passthrough-cargo-options]

Subcommands:
  init      Scaffold a brand-new Rust binary workspace from scratch
  check     Verify syntax & type safety using global cached crates
  test      Run the full workspace unit test suite inside Alpine
  build     Compile and export optimized static musl binaries
  run       (Default) Build, test, and instantly execute inside sandbox
  update    Pull the latest engine upgrades natively from GitHub
  help      Display this unified architecture help documentation

Core Tool Modifiers & Flags:
  -port <int>  Map internal container network bridges out to host OS
  -offline     Strict air-gap execution. Disconnects internet bridges
  -refresh     Safely pull the newest crate versions into the central cache
  -ipv4        Enforce IPv4 stacks (Fixes WSL2 network freezing bugs)

=======================================================================
"@ -ForegroundColor Gray
    Exit
}

if ($Action -eq "update") {
    Show-Header "Updating engine source files from GitHub..." "Cyan"
    git -C $PSScriptRoot pull
    Exit
}

if ($Action -eq "init") {
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "   alprust Project Scaffolding Engine     " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    $currentFolder = (Get-Item .).Name
    
    $name = Read-Host "📦 Project Name [Default: $currentFolder]"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $currentFolder }
    
    $version = Read-Host "🏷️ Version [Default: 0.1.0]"
    if ([string]::IsNullOrWhiteSpace($version)) { $version = "0.1.0" }

    $edition = Read-Host "🦀 Rust Edition (e.g., 2021, 2024) [Default: 2021]"
    if ([string]::IsNullOrWhiteSpace($edition)) { $edition = "2021" }
    
    $depsInput = Read-Host "⚙️ Dependencies (comma separated, e.g., tokio@1, serde)"
    
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
edition = "$edition"

[dependencies]
$tomlDeps
"@
    $cargoToml | Out-File "Cargo.toml" -Encoding utf8 -Force

    if (-not (Test-Path "src")) { New-Item -ItemType Directory -Path "src" | Out-Null }
    $mainRs = @"
fn main() {
    println!("Hello from alprust scaffolded project: $name (Edition $edition)!");
}
"@
    $mainRs | Out-File "src/main.rs" -Encoding utf8 -Force

    Write-Host "`n✨ Success! Rust project '$name' scaffolded cleanly!" -ForegroundColor Green
    Exit
}

$dockerCheck = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "[Error] Docker Desktop is not running! Please initialize your daemon first."
    Exit
}

if (-not (Test-Path "Cargo.toml")) {
    Write-Error "[Error] No Cargo.toml discovered. Ensure your shell paths match a Rust root directory!"
    Exit
}

$cargoContent = Get-Content "Cargo.toml" -Raw
if ($cargoContent -match 'name\s*=\s*"([^"]+)"') {
    $binaryName = $Matches[1]
    Write-Host "`nTarget Workspace Detected: " -NoNewline -ForegroundColor Gray
    Write-Host $binaryName -ForegroundColor Yellow
} else {
    Write-Error "[Error] Unable to isolate package structural definitions inside Cargo.toml."
    Exit
}

if ($Port -gt 0 -and $Action -eq "run") {
    $originalPort = $Port
    while (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue) {
        $Port++
    }
    if ($Port -ne $originalPort) {
        Write-Host "[Warning] Port $originalPort is currently busy! Auto-shifting link to open slot: $Port" -ForegroundColor Yellow
    }
}

$cargoFlagsStr = if ($PassthroughFlags) { $PassthroughFlags -join " " } else { "" }

$buildArgs = @("--progress=quiet") 
$runArgs = @()

if ($Offline) {
    Show-Header "Strict Air-Gap Mode Active. Virtual networks severed." "Magenta"
    $buildArgs += @("--network", "none", "--pull=false")
    $runArgs += "--pull=never"
}

if ($IPv4) {
    Show-Header "Enforcing defensive IPv4 host mapping fallback layers..." "Cyan"
    $buildArgs += @("--network", "host")
    $runArgs += @("--sysctl", "net.ipv6.conf.all.disable_ipv6=1")
}

$buildArgs += @("--build-arg", "CARGO_FLAGS=$cargoFlagsStr")
if ($Refresh) {
    Show-Header "Atomic refresh triggered. Scanning upstream for newer package variations..." "Yellow"
    $buildArgs += @("--build-arg", "REFRESH_CACHE=true")
} else {
    $buildArgs += @("--build-arg", "REFRESH_CACHE=false")
}

$cacheHeader = @"
FROM rust:alpine AS base
ARG CARGO_FLAGS
ARG REFRESH_CACHE=false
WORKDIR /app
COPY . .
RUN --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    if [ "`$REFRESH_CACHE" = "true" ]; then cargo update; fi
"@

switch ($Action) {
    "check" {
        Show-Header "Running syntax and type validation sweeps..." "Cyan"
        $dockerfileContent = @"
$cacheHeader
RUN --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo check `$CARGO_FLAGS
"@
        $buildArgs += @("-f", "-", ".")
        $dockerfileContent | docker build @buildArgs
        if ($LASTEXITCODE -eq 0) { Show-Header "Syntax verification passed cleanly!" "Green" }
        Exit
    }
    "test" {
        Show-Header "Running internal unit and integration tests..." "Cyan"
        $dockerfileContent = @"
$cacheHeader
RUN --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo test `$CARGO_FLAGS
"@
        $buildArgs += @("-f", "-", ".")
        $dockerfileContent | docker build @buildArgs
        if ($LASTEXITCODE -eq 0) { Show-Header "All tests passed flawlessly!" "Green" }
        Exit
    }
    Default {
        $dockerfileContent = @"
FROM rust:alpine AS builder
ARG BIN_NAME
ARG CARGO_FLAGS
ARG REFRESH_CACHE=false
WORKDIR /app
COPY . .
RUN --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    if [ "`$REFRESH_CACHE" = "true" ]; then cargo update; fi
RUN --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo test `$CARGO_FLAGS
RUN --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo build --release --target x86_64-unknown-linux-musl `$CARGO_FLAGS

FROM scratch
ARG BIN_NAME
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/`$BIN_NAME /
"@
        $buildArgs += @("--build-arg", "BIN_NAME=$binaryName", "-f", "-", "-o", "./output", ".")
        
        Show-Header "Compiling static Alpine production binary asset pipeline..." "Cyan"
        if (Test-Path "output") { Remove-Item "output" -Recurse -Force }
        
        $dockerfileContent | docker build @buildArgs
        
        if ($LASTEXITCODE -eq 0 -and $Action -eq "run") {
            Show-Header "Static cross-compilation pipeline executed flawlessly!" "Green"
            Show-Header "Booting sandbox environment application loop... (Press Ctrl+C to terminate cleanly)" "Cyan"
            
            $hostOutputDir = (Get-Item .\output).FullName
            $runArgs += @("--rm", "-it", "--init")
            
            if ($Port -gt 0) {
                Write-Host "`n-------------------------------------------------------" -ForegroundColor Gray
                Write-Host " 👉 Host OS Access URL:     http://localhost:$Port" -ForegroundColor Green
                Write-Host " 👉 Isolated Container URL: http://0.0.0.0:$Port" -ForegroundColor Yellow
                Write-Host "-------------------------------------------------------`n" -ForegroundColor Gray
                $runArgs += @("-p", "${Port}:${Port}", "-e", "PORT=$Port")
            }
            
            $runArgs += @("-v", "${hostOutputDir}:/app", "alpine", "/app/$binaryName")
            docker run @runArgs
        } elseif ($LASTEXITCODE -eq 0) {
            Show-Header "Static standalone binary extracted cleanly to ./output/$binaryName" "Green"
        } else {
            Write-Error "[Error] Build pipeline halted due to code compilation failures."
        }
    }
}