[CmdletBinding()]
param (
    [Parameter(Position=0)]
    [ValidateSet("run", "check", "test", "build", "update", "init", "help", "clean")]
    [string]$Action = "run",
    
    [switch]$Offline,
    [switch]$IPv4,
    [switch]$Refresh,
    
    [ValidateRange(0, 65535)]
    [int]$Port = 0,

    # Dynamic fallback for arbitrary edge-case Cargo options
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$PassthroughFlags
)

$Verbose = $PSBoundParameters.ContainsKey('Verbose')

# Unicode emoji definitions using character codes for system encoding/locale immunity
$EmojiRocket   = [char]::ConvertFromUtf32(0x1F680)
$EmojiBox      = [char]::ConvertFromUtf32(0x1F4E6)
$EmojiTag      = [char]::ConvertFromUtf32(0x1F3F7)
$EmojiCrab     = [char]::ConvertFromUtf32(0x1F980)
$EmojiGear     = [char]::ConvertFromUtf32(0x2699)
$EmojiSparkles = [char]::ConvertFromUtf32(0x2728)
$EmojiFire     = [char]::ConvertFromUtf32(0x1F525)
$EmojiFinger   = [char]::ConvertFromUtf32(0x1F449)

function Show-Header ($Message, $Color = "Cyan") {
    Write-Host "`n[alprust] $Message" -ForegroundColor $Color
}

if ($Action -eq "help") {
    Write-Host @"

=======================================================================
   alprust CLI $EmojiRocket - Ultra-lean Alpine Linux Compilation Suite
=======================================================================
Created and maintained by codesbysuman.

Usage:
  alprust [subcommand] [flags] [passthrough-cargo-options]

Subcommands:
  init      Scaffold a brand-new Rust binary workspace from scratch
  check     Verify syntax & type safety using global cached crates
  test      Run the full workspace unit test suite inside Alpine
  clean     Clear target compilation cache for the current workspace
  build     Compile and export optimized static musl binaries
  run       (Default) Build, test, and instantly execute inside sandbox
  update    Pull the latest engine upgrades natively from GitHub
  help      Display this unified architecture help documentation

Core Tool Modifiers & Flags:
  -port <int>  Map internal container network bridges out to host OS
  -offline     Strict air-gap execution. Disconnects internet bridges
  -refresh     Safely pull the newest crate versions into the central cache
  -verbose     Stream unfiltered raw execution and compilation logs
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
    
    if (Test-Path "Cargo.toml") {
        $choice = Read-Host "[Warning] Cargo.toml already exists! Overwrite? (y/N)"
        if ($choice -notmatch '^[yY]') {
            Write-Host "Scaffolding aborted." -ForegroundColor Yellow
            Exit 0
        }
    }
    
    $currentFolder = (Get-Item .).Name
    
    $name = Read-Host "$EmojiBox Project Name [Default: $currentFolder]"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $currentFolder }
    
    $version = Read-Host "$EmojiTag Version [Default: 0.1.0]"
    if ([string]::IsNullOrWhiteSpace($version)) { $version = "0.1.0" }

    $edition = Read-Host "$EmojiCrab Rust Edition (e.g., 2021, 2024) [Default: 2024]"
    if ([string]::IsNullOrWhiteSpace($edition)) { $edition = "2024" }
    
    $rustVersionInput = Read-Host "Target Rust Version (e.g., 1.80, or press Enter for latest Alpine)"

    $depsInput = Read-Host "$EmojiGear Dependencies (comma separated, e.g., tokio@1, serde)"
    
    $tomlDeps = ""
    if (-not [string]::IsNullOrWhiteSpace($depsInput)) {
        foreach ($dep in ($depsInput -split ',')) {
            $dep = $dep.Trim()
            if ($dep -match '^([^@]+)@(.+)$') {
                $tomlDeps += "    $($Matches[1].Trim()) = `"$($Matches[2].Trim())`"`n"
            } elseif ($dep -ne "") {
                $tomlDeps += "    $dep = `"*`"`n"
            }
        }
    }

    $packageLines = @(
        "[package]"
        "name = `"$name`""
        "version = `"$version`""
        "edition = `"$edition`""
    )
    if (-not [string]::IsNullOrWhiteSpace($rustVersionInput)) {
        $packageLines += "rust-version = `"$($rustVersionInput.Trim())`""
    }
    $packageBlock = $packageLines -join "`n"

    $cargoToml = @"
$packageBlock

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

    Write-Host "`n$EmojiSparkles Success! Rust project '$name' scaffolded cleanly!" -ForegroundColor Green
    Exit 0
}

# Verify Docker execution environment
try {
    $null = Get-Command docker -ErrorAction Stop
    $dockerCheck = docker info 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[Error] Docker Desktop is not running! Please initialize your daemon first." -ForegroundColor Red
        Exit 1
    }
} catch {
    Write-Host "[Error] Docker CLI is not installed or not in your system PATH." -ForegroundColor Red
    Exit 1
}

if (-not (Test-Path "Cargo.toml")) {
    Write-Host "[Error] No Cargo.toml discovered. Ensure your shell paths match a Rust root directory!" -ForegroundColor Red
    Exit 1
}

$cargoContent = Get-Content "Cargo.toml" -Raw
if ($cargoContent -match '(?ms)^\[package\].*?^name\s*=\s*["'']([^"'']+)["'']') {
    $binaryName = $Matches[1]
    Write-Host "`nTarget Workspace Detected: " -NoNewline -ForegroundColor Gray
    Write-Host $binaryName -ForegroundColor Yellow
} else {
    Write-Host "[Error] Unable to isolate package structural definitions inside Cargo.toml." -ForegroundColor Red
    Exit 1
}

$rustVersion = "alpine"
if ($cargoContent -match '(?ms)^\[package\].*?^rust-version\s*=\s*["'']([^"'']+)["'']') {
    $rustVersion = "$($Matches[1])-alpine"
    Write-Host "Targeting Rust Version: " -NoNewline -ForegroundColor Gray
    Write-Host $Matches[1] -ForegroundColor Yellow
}

function Test-PortBusy ([int]$PortNumber) {
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $PortNumber)
        $listener.Start()
        return $false
    } catch {
        return $true
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

if ($Port -gt 0 -and $Action -eq "run") {
    $originalPort = $Port
    while (Test-PortBusy $Port) {
        $Port++
    }
    if ($Port -ne $originalPort) {
        Write-Host "[Warning] Port $originalPort is currently busy! Auto-shifting link to open slot: $Port" -ForegroundColor Yellow
    }
}

$cargoFlagsStr = if ($PassthroughFlags) { $PassthroughFlags -join " " } else { "" }

# Configure BuildKit streaming modes based on verbosity preferences
$progressMode = if ($Verbose) { "plain" } else { "quiet" }
$buildArgs = @("--progress=$progressMode") 
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
FROM rust:$rustVersion AS base
ARG CARGO_FLAGS
ARG REFRESH_CACHE=false
WORKDIR /app
COPY . .
RUN --mount=type=cache,id=alprust-target-$binaryName,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    if [ "`$REFRESH_CACHE" = "true" ]; then cargo update; fi
"@

# --- CORE IN-MEMORY STREAM EXECUTION FUNCTION WITH TIME TICKERS ---
function Execute-BuildWithTicker ($DockerfileContent, $Arguments) {
    $tempDockerfile = Join-Path $PWD ".alprust.Dockerfile.tmp"
    $tempOut = Join-Path $PWD ".alprust.stdout.tmp"
    $tempErr = Join-Path $PWD ".alprust.stderr.tmp"
    
    # Write Dockerfile content to temp file
    $DockerfileContent | Out-File $tempDockerfile -Encoding utf8 -Force
    
    # Pre-clean output redirection files
    if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
    if (Test-Path $tempErr) { Remove-Item $tempErr -Force }
    
    $dockerArgs = @("build", "-f", $tempDockerfile) + $Arguments
    
    if ($Verbose) {
        $proc = Start-Process -FilePath "docker" -ArgumentList $dockerArgs -NoNewWindow -PassThru -Wait
        return $proc.ExitCode
    }

    $proc = $null
    try {
        $proc = Start-Process -FilePath "docker" -ArgumentList $dockerArgs -NoNewWindow -PassThru `
            -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr
            
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited) {
            $elapsed = [string]::Format("{0:d2}s", [int][Math]::Floor($sw.Elapsed.TotalSeconds))
            Write-Host "`r[alprust] Processing compilation asset layers... ($elapsed)" -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 100
        }
        $sw.Stop()
        Write-Host "`r[alprust] Processing compilation asset layers... Done!       " -ForegroundColor Cyan
        
        $exitCode = $proc.ExitCode
        
        if ($exitCode -ne 0) {
            Write-Host "`n=======================================================" -ForegroundColor Red
            Write-Host " $EmojiFire BUILD FAILURE DETECTED INSIDE THE CONTAINER" -ForegroundColor Red
            Write-Host "=======================================================" -ForegroundColor Red
            
            if (Test-Path $tempErr) {
                $err = Get-Content $tempErr -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($err)) { Write-Host $err -ForegroundColor DarkRed }
            }
            if (Test-Path $tempOut) {
                $out = Get-Content $tempOut -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($out)) { Write-Host $out -ForegroundColor Gray }
            }
        }
        return $exitCode
    } catch {
        Write-Host "`n[Error] Failed to execute docker process: $_" -ForegroundColor Red
        return 1
    } finally {
        if ($null -ne $proc -and -not $proc.HasExited) {
            try { $proc.Kill() } catch {}
        }
        if (Test-Path $tempDockerfile) { Remove-Item $tempDockerfile -Force }
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
        if (Test-Path $tempErr) { Remove-Item $tempErr -Force }
    }
}

# Manage temporary .dockerignore setup
$dockerIgnorePath = Join-Path $PWD ".dockerignore"
$hasDockerIgnore = Test-Path $dockerIgnorePath
$originalIgnoreContent = $null

try {
    # Set up temporary .dockerignore to optimize Docker build context size
    if ($hasDockerIgnore) {
        $originalIgnoreContent = Get-Content $dockerIgnorePath -Raw
        $additionalIgnore = "`n# alprust temporary exclusions`ntarget`ndist`n.git`n.alprust.*.tmp`n"
        Add-Content $dockerIgnorePath $additionalIgnore -ErrorAction SilentlyContinue
    } else {
        $tempIgnore = "# alprust temporary exclusions`ntarget`ndist`n.git`n.alprust.*.tmp`n"
        $tempIgnore | Out-File $dockerIgnorePath -Encoding utf8 -Force
    }

    switch ($Action) {
        "check" {
            Show-Header "Running syntax and type validation sweeps..." "Cyan"
            $dockerfileContent = @"
$cacheHeader
RUN --mount=type=cache,id=alprust-target-$binaryName,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo check `$CARGO_FLAGS
"@
            $code = Execute-BuildWithTicker $dockerfileContent ($buildArgs + @("."))
            if ($code -eq 0) { Show-Header "Syntax verification passed cleanly!" "Green" } else { Exit $code }
        }
        "test" {
            Show-Header "Running internal unit and integration tests..." "Cyan"
            $dockerfileContent = @"
$cacheHeader
RUN --mount=type=cache,id=alprust-target-$binaryName,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo test `$CARGO_FLAGS
"@
            $code = Execute-BuildWithTicker $dockerfileContent ($buildArgs + @("."))
            if ($code -eq 0) { Show-Header "All tests passed flawlessly!" "Green" } else { Exit $code }
        }
        "clean" {
            Show-Header "Clearing target compilation cache for $binaryName..." "Cyan"
            $dockerfileContent = @"
FROM rust:$rustVersion
ARG BIN_NAME
WORKDIR /app
COPY Cargo.toml .
RUN --mount=type=cache,id=alprust-target-`$BIN_NAME,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo clean
"@
            $cleanArgs = $buildArgs + @("--build-arg", "BIN_NAME=$binaryName", ".")
            $code = Execute-BuildWithTicker $dockerfileContent $cleanArgs
            if ($code -eq 0) { Show-Header "Compilation cache cleared cleanly!" "Green" } else { Exit $code }
        }
        Default {
            $dockerfileContent = @"
FROM rust:$rustVersion AS builder
ARG BIN_NAME
ARG CARGO_FLAGS
ARG REFRESH_CACHE=false
WORKDIR /app
COPY . .
RUN --mount=type=cache,id=alprust-target-`$BIN_NAME,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    if [ "`$REFRESH_CACHE" = "true" ]; then cargo update; fi
RUN --mount=type=cache,id=alprust-target-`$BIN_NAME,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo test `$CARGO_FLAGS
RUN --mount=type=cache,id=alprust-target-`$BIN_NAME,target=/app/target \
    --mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db \
    --mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache \
    --mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db \
    cargo build --release `$CARGO_FLAGS && \
    (cp /app/target/release/`$BIN_NAME /app/`$BIN_NAME 2>/dev/null || cp /app/target/*/release/`$BIN_NAME /app/`$BIN_NAME 2>/dev/null || cp /app/target/*/*/release/`$BIN_NAME /app/`$BIN_NAME 2>/dev/null)

FROM scratch
ARG BIN_NAME
COPY --from=builder /app/`$BIN_NAME /
"@
            $runBuildArgs = $buildArgs + @("--build-arg", "BIN_NAME=$binaryName", "-o", "./dist", ".")
            
            Show-Header "Compiling static Alpine production binary asset pipeline..." "Cyan"
            if (Test-Path "dist") { Remove-Item "dist" -Recurse -Force }
            
            $code = Execute-BuildWithTicker $dockerfileContent $runBuildArgs
            
            if ($code -eq 0 -and $Action -eq "run") {
                Show-Header "Static cross-compilation pipeline executed flawlessly!" "Green"
                Show-Header "Booting sandbox environment application loop... (Press Ctrl+C to terminate cleanly)" "Cyan"
                
                $hostOutputDir = (Get-Item .\dist).FullName
                $runArgs += @("--rm", "-it", "--init")
                
                if ($Port -gt 0) {
                    Write-Host "`n-------------------------------------------------------" -ForegroundColor Gray
                    Write-Host " $EmojiFinger Host OS Access URL:     http://localhost:$Port" -ForegroundColor Green
                    Write-Host " $EmojiFinger Isolated Container URL: http://0.0.0.0:$Port" -ForegroundColor Yellow
                    Write-Host "-------------------------------------------------------`n" -ForegroundColor Gray
                    $runArgs += @("-p", "${Port}:${Port}", "-e", "PORT=$Port")
                }
                
                $runArgs += @("-v", "${hostOutputDir}:/app", "alpine", "/app/$binaryName")
                docker run @runArgs
            } elseif ($code -eq 0) {
                Show-Header "Static standalone binary extracted cleanly to ./dist/$binaryName" "Green"
            } else {
                Exit $code
            }
        }
    }
} finally {
    # Restore or clean up temporary .dockerignore file
    if ($hasDockerIgnore) {
        if ($null -ne $originalIgnoreContent) {
            $originalIgnoreContent | Out-File $dockerIgnorePath -Encoding utf8 -Force
        }
    } else {
        if (Test-Path $dockerIgnorePath) {
            Remove-Item $dockerIgnorePath -Force
        }
    }
}
