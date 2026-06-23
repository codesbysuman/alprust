# alprust 🚀

`alprust` is a lightweight, zero-footprint CLI tool designed to compile ultra-lean, static Rust binaries targeted specifically for **Alpine Linux bare-metal instances** (ideal for low-resource environments like a 2GB RAM free-tier VPS).

Created and maintained by **codesbysuman**.

---

## The Problem It Solves

When deploying Rust applications to a minimalist Alpine Linux environment, you must target the lightweight `musl` standard library instead of the traditional `glibc`.

Trying to set up this cross-compilation toolchain **natively or reliably on Windows or macOS is notoriously frustrating**, often requiring heavy dependencies, complex linker configurations, or broken environment variables. While Docker solves this runtime isolation issue, manually writing, managing, and maintaining custom multi-stage `Dockerfiles` for every single microservice introduces unnecessary friction and clutters your codebase.

**`alprust` completely removes this hassle.** It handles the entire compilation, checking, testing, scaffolding, and runtime emulation pipeline directly in-memory via streamed Docker processing.

---

## Features

* **Zero Codebase Clutter:** Operates entirely in-memory. It pipes build instructions straight to the Docker daemon via `stdin`, leaving your local repository completely clean.
* **Quick Project Scaffolding:** Includes an automated initializer to instantly spin up standard Rust binary template directories and map dependencies using simple, human-readable console prompts.
* **Native Subcommands:** Replaces raw Cargo calls seamlessly with commands like `alprust check` and `alprust test` run inside precise Alpine contexts.
* **Persistent Cache Mounting:** Leverages BuildKit layer caching to save and reuse downloaded dependency crates across compilation runs. **Reduces internet data consumption to zero on subsequent checks or builds.**
* **Edge-Case Ready (Flag Passthrough):** Future-proof design accepts arbitrary Cargo arguments (like `--features`, `--bin`, or `--offline`) seamlessly from the CLI without breaking.
* **Automatic IPv4 Network Guardrail:** Includes an explicit `-ipv4` switch to patch the notorious Windows/WSL2 IPv6 black-hole routing bug which causes Alpine containers to freeze on network calls.
* **Seamless Local Updates:** Includes a built-in `alprust update` command that updates the utility seamlessly via Git without altering your terminal's current working directory (`cwd`).
* **Dynamic Configuration:** Automatically parses your `Cargo.toml` at runtime to isolate package markers and direct output binary paths.

---

## Prerequisites

Before installing, ensure you have **Docker Desktop** installed, running, and accessible via your system terminal.

---

## Quick Start & Installation

Run the explicit command below for your operating system to clone the repository into your user home directory, navigate into the folder, and execute the installation setup in one shot:

### 🛠️ On Windows (PowerShell)

Ensure your PowerShell execution policy allows running local scripts, then execute this command:

```powershell
git clone https://github.com/codesbysuman/alprust.git ~\alprust; cd ~\alprust; Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force; .\install.ps1

```

*Note: Please close and restart your terminal window after the script finishes to refresh your environment PATH variables.*

### 🍏 / 🐧 On macOS or Linux

Open your terminal and run this command:

```bash
git clone https://github.com/codesbysuman/alprust.git ~/alprust && cd ~/alprust && bash install.sh

```

---

## Updating alprust

You can update `alprust` directly from your terminal at any time. The tool targets its own source directory to pull changes from GitHub without altering your terminal's current working directory (`cwd`):

```bash
alprust update

```

---

## Usage & Subcommands

Simply navigate to your desired workspace or the root directory of an existing Rust project and call your action:

### 1. Quick Project Scaffolding

Creates a clean, standard Rust binary structure inside an empty directory. It prompts for configuration strings using normal human text:

```bash
alprust init

```

*Prompt Input Reference:*

* **Project Name:** `tasks-processor` (Defaults to your current directory name if left blank)
* **Version:** `1.0.0` (Defaults to `0.1.0` if left blank)
* **Dependencies:** `tokio@1.35, serde, axum@0.7.2` (Specifying no `@version` configuration defaults to the latest `*` package wildcard)

### 2. Verification Checking

Validates compilation integrity and tracks architectural warnings inside the Alpine Linux environment without triggering a full production build:

```bash
alprust check

```

### 3. Isolated Test Executions

Isolates and fires your project's full test suite inside an active Alpine context with layer caching active:

```bash
alprust test

```

### 4. Production Compilation Only

Compiles and extracts the bare-metal static binary straight into your local `./output/` folder without launching a live verification container sandbox:

```bash
alprust build

```

### 5. Continuous Dev Loop (Default Action)

Runs test workflows, outputs the static binary, and **immediately boots it live** inside an Alpine runtime container instance:

```bash
alprust
# Or explicitly:
alprust run

```

---

## Advanced Configurations & Passthroughs

### 1. Port Forwarding

* **`-port <number>`**: Exposes custom network bridges out to your host machine (e.g., `alprust -port 3000`).

### 2. Tool Modifiers

* **`-offline`**: Forces Docker to rely exclusively on local baseline image target caches (e.g., `alprust check -offline`).
* **`-ipv4`**: Activates defensive routing parameters. Use this flag if your container compilation hangs or times out on Windows/WSL2 due to missing local host IPv6 packet mappings (e.g., `alprust run -ipv4`).

### 3. Edge-Case Cargo Flags Passthrough

Any arbitrary argument not captured by system-specific modifiers will pass straight down into the `cargo` executor inside the container:

```bash
# Pass specific feature flag profiles
alprust build --features env_logger

# Target a highly specific binary module in a multi-bin codebase
alprust check --bin specialized_worker

# Combine tool-specific fallback flags with standard cargo features
alprust run -ipv4 -port 8080 --features "nitro local-testing"

```

---

## 💡 Testing Network Endpoints Locally

If you are exposing custom port parameters to interact with an API or test a `/health` endpoint while `alprust` runs your container sandbox, ensure your Rust code binds to network address `0.0.0.0` instead of `127.0.0.1`:

```rust
// In your main.rs setup (Axum, Actix, Tokio, etc.)
let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;

```

Once booted via `alprust -port 8080`, open your browser or Postman on your host machine and hit: `http://localhost:8080/health`.

Press **`Ctrl + C`** in your terminal to shut down the runtime sandbox cleanly. Your production-ready binary will be waiting natively inside your project's new `./output/` directory, ready to be copied directly onto your bare VPS metal.