[CmdletBinding()]
param (
    [Parameter(Position=0)]
    [ValidateSet("run", "check", "test", "build", "self-update", "init", "help", "clean")]
    [string]$Action = "run",
    
    [switch]$Offline,
    [switch]$IPv4,
    [switch]$Refresh,
    [switch]$All,
    
    [ValidateRange(0, 65535)]
    [int]$Port = 0,

    # Dynamic fallback for arbitrary edge-case Cargo options
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$PassthroughFlags
)

# Enforce UTF-8 encoding for console output and command piping
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$AlprustVersion = 24

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
   alprust CLI v$AlprustVersion $EmojiRocket - Ultra-lean Alpine Linux Compilation Suite
======================================================================="
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
  self-update Pull the latest engine upgrades natively from GitHub
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

if ($Action -eq "self-update") {
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

function Get-PackageVal ($targetKey) {
    if (-not (Test-Path "Cargo.toml")) { return $null }
    $inPackage = $false
    foreach ($line in (Get-Content "Cargo.toml")) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#") -or [string]::IsNullOrEmpty($trimmed)) { continue }
        
        if ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
            $section = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
            if ($section -eq "package") {
                $inPackage = $true
            } else {
                $inPackage = $false
            }
            continue
        }
        
        if ($inPackage) {
            if ($trimmed -match "^$targetKey\s*=") {
                $parts = $trimmed -split "=", 2
                if ($parts.Count -eq 2) {
                    $val = $parts[1].Trim()
                    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                        return $val.Substring(1, $val.Length - 2)
                    }
                    return $val
                }
            }
        }
    }
    return $null
}

if (-not (Test-Path "Cargo.toml")) {
    Write-Host "[Error] No Cargo.toml discovered. Ensure your shell paths match a Rust root directory!" -ForegroundColor Red
    Exit 1
}

$binaryName = Get-PackageVal "name"
if ($null -ne $binaryName) {
    Write-Host "`nTarget Workspace Detected: " -NoNewline -ForegroundColor Gray
    Write-Host $binaryName -ForegroundColor Yellow
} else {
    Write-Host "[Error] Unable to isolate package structural definitions inside Cargo.toml." -ForegroundColor Red
    Exit 1
}

$rustVersion = "alpine"
$parsed_ver = Get-PackageVal "rust-version"
if ($null -ne $parsed_ver) {
    $rustVersion = "$parsed_ver-alpine"
    Write-Host "Targeting Rust Version: " -NoNewline -ForegroundColor Gray
    Write-Host $parsed_ver -ForegroundColor Yellow
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

# Sanitize Cargo flags to prevent shell injection inside the container
if ($cargoFlagsStr -match '[;\&\|$\`><\r\n]') {
    Write-Host "[Error] Invalid/dangerous characters detected in Cargo flags." -ForegroundColor Red
    Exit 1
}

# Configure BuildKit streaming modes. We always use "plain" to capture detailed compiler logs in the background,
# but we control the visibility dynamically depending on verbosity settings.
$progressMode = "plain"
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

$cacheBypass = [Guid]::NewGuid().Guid
$buildArgs += @("--build-arg", "CARGO_FLAGS=$cargoFlagsStr", "--build-arg", "CACHE_BYPASS=$cacheBypass")
if ($Refresh) {
    Show-Header "Atomic refresh triggered. Scanning upstream for newer package variations..." "Yellow"
    $buildArgs += @("--build-arg", "REFRESH_CACHE=true")
} else {
    $buildArgs += @("--build-arg", "REFRESH_CACHE=false")
}

$cacheMounts = @(
    "--mount=type=cache,id=alprust-target-$binaryName,target=/app/target"
    "--mount=type=cache,id=alprust-registry-db,target=/usr/local/cargo/registry/db"
    "--mount=type=cache,id=alprust-registry-cache,target=/usr/local/cargo/registry/cache"
    "--mount=type=cache,id=alprust-registry-index,target=/usr/local/cargo/registry/index"
    "--mount=type=cache,id=alprust-registry-src,target=/usr/local/cargo/registry/src"
    "--mount=type=cache,id=alprust-git-db,target=/usr/local/cargo/git/db"
    "--mount=type=cache,id=alprust-git-checkouts,target=/usr/local/cargo/git/checkouts"
) -join " \`n    "

$cacheHeader = @"
FROM rust:$rustVersion AS base
ARG CARGO_FLAGS
ARG REFRESH_CACHE=false
ARG CACHE_BYPASS
WORKDIR /app
COPY . .
RUN echo `$CACHE_BYPASS > /dev/null
RUN $cacheMounts \
    if [ "`$REFRESH_CACHE" = "true" ]; then cargo update; fi
"@

# --- CORE IN-MEMORY STREAM EXECUTION FUNCTION WITH TIME TICKERS ---
function Execute-BuildWithTicker ($DockerfileContent, $Arguments) {
    $tempDir = [System.IO.Path]::GetTempPath()
    $tempId = [Guid]::NewGuid().Guid
    $tempDockerfile = Join-Path $tempDir "alprust_dockerfile_$tempId.tmp"
    $tempOut = Join-Path $tempDir "alprust_stdout_$tempId.tmp"
    $tempErr = Join-Path $tempDir "alprust_stderr_$tempId.tmp"
    
    # Write Dockerfile content to temp file
    $DockerfileContent | Out-File $tempDockerfile -Encoding utf8 -Force
    
    # Pre-clean output redirection files
    if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
    if (Test-Path $tempErr) { Remove-Item $tempErr -Force }
    
    # Format arguments as a single string for cmd.exe
    $escapedArgs = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '`"' + $_.Replace('"', '\"') + '`"'
        } else {
            $_
        }
    }
    $dockerArgsStr = $escapedArgs -join " "
    $dockerCmd = "build -f `"$tempDockerfile`" $dockerArgsStr"

    if ($Verbose) {
        & cmd /c "docker $dockerCmd"
        return $LASTEXITCODE
    }

    $job = $null
    try {
        $workspacePath = $PWD.Path
        $job = Start-Job -ScriptBlock {
            param($dockerCmd, $tempOut, $tempErr, $workspacePath)
            Set-Location $workspacePath
            & cmd /c "docker $dockerCmd > `"$tempOut`" 2> `"$tempErr`""
            return $LASTEXITCODE
        } -ArgumentList $dockerCmd, $tempOut, $tempErr, $workspacePath
            
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($job.State -eq "Running") {
            $elapsed = [string]::Format("{0:d2}s", [int][Math]::Floor($sw.Elapsed.TotalSeconds))
            Write-Host "`r[alprust] Processing compilation asset layers... ($elapsed)" -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 100
        }
        $sw.Stop()
        Write-Host "`r[alprust] Processing compilation asset layers... Done!       " -ForegroundColor Cyan
        
        $exitCode = Receive-Job -Job $job
        
        if ($exitCode -ne 0) {
            Write-Host "[alprust] $EmojiFire Build failure detected inside the container" -ForegroundColor Red
            
            $logLines = @()
            if (Test-Path $tempErr) { $logLines += Get-Content $tempErr }
            if (Test-Path $tempOut) { $logLines += Get-Content $tempOut }

            $filteredLines = @()
            $inFooter = $false
            foreach ($line in $logLines) {
                # Stop parsing once we hit the BuildKit failure footer demarcation
                if ($line -match '^------+$' -or $line -match '^ > \[builder') {
                    $inFooter = $true
                }
                if ($inFooter) { continue }

                # Skip standard Docker/BuildKit setup noise
                if ($line -match '^#0 building with') { continue }
                if ($line -match 'docker-desktop://' -or $line -match 'View build details:') { continue }
                if ($line -match 'alprust_dockerfile_.*\.tmp:\d+') { continue }
                
                # Strip BuildKit prefix: e.g. "#9 0.693    Compiling..." or "#9 ..."
                $cleanLine = $line
                if ($line -match '^#\d+\s+[\d.]+\s+(.*)$') {
                    $cleanLine = $Matches[1]
                } elseif ($line -match '^#\d+\s+(.*)$') {
                    $cleanLine = $Matches[1]
                }

                # Filter out structural Docker steps and BuildKit metadata
                if ($cleanLine -match '^\[[a-zA-Z0-9_-]+ \d+/\d+\]') { continue }
                if ($cleanLine -match '^\[internal\]') { continue }
                if ($cleanLine -match '^(DONE|CACHED|resolve|transferring|exporting|ERROR:)\s*') { continue }
                
                $filteredLines += $cleanLine
            }
            # Trim leading empty lines
            $startIndex = 0
            while ($startIndex -lt $filteredLines.Count -and [string]::IsNullOrWhiteSpace($filteredLines[$startIndex])) {
                $startIndex++
            }
            
            # Trim trailing empty lines
            $endIndex = $filteredLines.Count - 1
            while ($endIndex -ge $startIndex -and [string]::IsNullOrWhiteSpace($filteredLines[$endIndex])) {
                $endIndex--
            }

            $trimmedLines = @()
            if ($startIndex -le $endIndex) {
                $trimmedLines = $filteredLines[$startIndex..$endIndex]
            }

            if ($trimmedLines.Count -gt 0) {
                Write-Host "`n[Compiler Output]:" -ForegroundColor Yellow
                foreach ($fLine in $trimmedLines) {
                    if ($fLine -match '^error(\[|:)') {
                        Write-Host $fLine -ForegroundColor Red
                    } elseif ($fLine -match '^warning(\[|:)') {
                        Write-Host $fLine -ForegroundColor Yellow
                    } elseif ($fLine -match '^note(\[|:)') {
                        Write-Host $fLine -ForegroundColor Cyan
                    } else {
                        Write-Host $fLine -ForegroundColor Gray
                    }
                }
            } else {
                # Fallback to cleaning and printing raw logs if no compiler errors parsed
                Write-Host "`nRaw execution log:" -ForegroundColor Yellow
                foreach ($line in $logLines) {
                    if ($line -notmatch 'docker-desktop://|View build details:|alprust_dockerfile_.*\.tmp:\d+') {
                        Write-Host $line -ForegroundColor DarkRed
                    }
                }
            }
        }
        return $exitCode
    } catch {
        Write-Host "`n[Error] Failed to execute docker process: $_" -ForegroundColor Red
        return 1
    } finally {
        if ($null -ne $job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempDockerfile) { Remove-Item $tempDockerfile -Force }
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
        if (Test-Path $tempErr) { Remove-Item $tempErr -Force }
    }
}

# Manage temporary .dockerignore setup
$dockerIgnorePath = Join-Path $PWD ".dockerignore"
$dockerIgnoreBackup = Join-Path $PWD ".dockerignore.alprust.bak"

# Recover from previous crashed run if backup exists
if (Test-Path $dockerIgnoreBackup) {
    if (Test-Path $dockerIgnorePath) {
        Remove-Item $dockerIgnorePath -Force -ErrorAction SilentlyContinue
    }
    Move-Item $dockerIgnoreBackup $dockerIgnorePath -Force -ErrorAction SilentlyContinue
}

$hasDockerIgnore = Test-Path $dockerIgnorePath
$scriptExitCode = 0

try {
    $exclusions = "`n# alprust temporary exclusions`ntarget`ndist`n.git`n.alprust.*.tmp`n.env*`n*.pem`n*.key`n*.der`n*.pfx`n*.p12`nnode_modules`n.idea`n.vscode`n*.sln`n*.sln.docstate`n*.suo`n*.tmp`n*.log`n*.zip`n*.tar.gz`n"
    if ($hasDockerIgnore) {
        # Copy original file to backup
        Copy-Item $dockerIgnorePath $dockerIgnoreBackup -Force
        # Append exclusions
        Add-Content $dockerIgnorePath $exclusions -ErrorAction SilentlyContinue
    } else {
        $exclusions | Out-File $dockerIgnorePath -Encoding utf8 -Force
    }

    switch ($Action) {
        "check" {
            Show-Header "Running syntax and type validation sweeps..." "Cyan"
            $dockerfileContent = @"
$cacheHeader
RUN $cacheMounts \
    cargo check `$CARGO_FLAGS
"@
            $code = Execute-BuildWithTicker $dockerfileContent ($buildArgs + @("."))
            if ($code -eq 0) { Show-Header "Syntax verification passed cleanly!" "Green" } else { $scriptExitCode = $code; return }
        }
        "test" {
            Show-Header "Running internal unit and integration tests..." "Cyan"
            $dockerfileContent = @"
$cacheHeader
RUN $cacheMounts \
    cargo test `$CARGO_FLAGS
"@
            $code = Execute-BuildWithTicker $dockerfileContent ($buildArgs + @("."))
            if ($code -eq 0) { Show-Header "All tests passed flawlessly!" "Green" } else { $scriptExitCode = $code; return }
        }
        "clean" {
            if ($All) {
                Show-Header "Pruning all system-wide BuildKit cache mounts..." "Yellow"
                docker builder prune --filter type=exec.cachemount -f
                $scriptExitCode = 0
                return
            }
            Show-Header "Clearing target compilation cache for $binaryName..." "Cyan"
            $dockerfileContent = @"
FROM rust:$rustVersion
ARG BIN_NAME
WORKDIR /app
COPY . .
RUN $cacheMounts \
    cargo clean
"@
            $cleanArgs = $buildArgs + @("--build-arg", "BIN_NAME=$binaryName", ".")
            $code = Execute-BuildWithTicker $dockerfileContent $cleanArgs
            if ($code -eq 0) { Show-Header "Compilation cache cleared cleanly!" "Green" } else { $scriptExitCode = $code; return }
        }
        Default {
            $dockerfileContent = @"
FROM rust:$rustVersion AS builder
ARG BIN_NAME
ARG CARGO_FLAGS
ARG REFRESH_CACHE=false
ARG CACHE_BYPASS
WORKDIR /app
COPY . .
RUN echo `$CACHE_BYPASS > /dev/null
RUN $cacheMounts \
    if [ "`$REFRESH_CACHE" = "true" ]; then cargo update; fi
RUN $cacheMounts \
    cargo test `$CARGO_FLAGS
RUN $cacheMounts \
    cargo build --release `$CARGO_FLAGS && \
    find /app/target -type f -name "`$BIN_NAME" -path "*/release/*" -exec cp {} /app/`$BIN_NAME \; -quit

FROM scratch
ARG BIN_NAME
COPY --from=builder /app/`$BIN_NAME /
"@
            $tempDistDir = "./.alprust.dist.tmp"
            if (Test-Path $tempDistDir) { Remove-Item $tempDistDir -Recurse -Force -ErrorAction SilentlyContinue }

            $runBuildArgs = $buildArgs + @("--build-arg", "BIN_NAME=$binaryName", "-o", $tempDistDir, ".")
            
            Show-Header "Compiling static Alpine production binary asset pipeline..." "Cyan"
            
            $code = Execute-BuildWithTicker $dockerfileContent $runBuildArgs
            
            if ($code -eq 0) {
                # Only replace the user's dist directory once compilation succeeds
                if (Test-Path "dist") { Remove-Item "dist" -Recurse -Force }
                Move-Item $tempDistDir "dist" -Force
                
                if ($Action -eq "run") {
                    Show-Header "Static cross-compilation pipeline executed flawlessly!" "Green"
                    Show-Header "Booting sandbox environment application loop... (Press Ctrl+C to terminate cleanly)" "Cyan"
                    
                    $hostOutputDir = (Get-Item .\dist).FullName
                    $runArgs += @("--rm", "-it", "--init")
                    
                    if ($Port -gt 0) {
                        Write-Host "-------------------------------------------------------" -ForegroundColor Gray
                        Write-Host " $EmojiFinger Host OS Access URL:     http://localhost:$Port" -ForegroundColor Green
                        Write-Host " $EmojiFinger Isolated Container URL: http://0.0.0.0:$Port" -ForegroundColor Yellow
                        Write-Host "-------------------------------------------------------`n" -ForegroundColor Gray
                        $runArgs += @("-p", "${Port}:${Port}", "-e", "PORT=$Port")
                    }
                    
                    $runArgs += @("-v", "${hostOutputDir}:/app", "alpine", "/app/$binaryName")
                    docker run @runArgs
                } else {
                    Show-Header "Static standalone binary extracted cleanly to ./dist/$binaryName" "Green"
                }
            } else {
                $scriptExitCode = $code
                return
            }
        }
    }
} finally {
    # Restore or clean up temporary .dockerignore file
    if (Test-Path $dockerIgnoreBackup) {
        Move-Item $dockerIgnoreBackup $dockerIgnorePath -Force -ErrorAction SilentlyContinue
    } elseif (-not $hasDockerIgnore -and (Test-Path $dockerIgnorePath)) {
        Remove-Item $dockerIgnorePath -Force -ErrorAction SilentlyContinue
    }
    
    # Clean up temporary dist folder if it remains
    $tempDistPath = Join-Path $PWD ".alprust.dist.tmp"
    if (Test-Path $tempDistPath) {
        Remove-Item $tempDistPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Exit $scriptExitCode
