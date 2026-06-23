# alprust 🚀

`alprust` is a lightweight, zero-footprint CLI tool designed to compile ultra-lean, static Rust binaries targeted specifically for **Alpine Linux bare-metal instances** (ideal for low-resource environments like a 2GB RAM free-tier VPS).

Created and maintained by **codesbysuman**.

---

## The Problem It Solves

When deploying Rust applications to a minimalist Alpine Linux environment, you must target the lightweight `musl` standard library instead of the traditional `glibc`.

Trying to set up this cross-compilation toolchain **natively or reliably on Windows or macOS is notoriously frustrating**, often requiring heavy dependencies, complex linker configurations, or broken environment variables. While Docker solves this runtime isolation issue, manually writing, managing, and maintaining custom multi-stage `Dockerfiles` for every single microservice introduces unnecessary friction and clutters your codebase.

**`alprust` completely removes this hassle.** It handles the entire compilation, checking, testing, and runtime emulation pipeline directly in-memory via streamed Docker processing.

---

## Features

* **Zero Codebase Clutter:** Operates entirely in-memory. It pipes build instructions straight to the Docker daemon via `stdin`, leaving your local repository completely clean.
* **Native Subcommands:** Replaces raw Cargo calls seamlessly with commands like `alprust check` and `alprust test` run inside precise Alpine contexts.
* **Dynamic Configuration:** Automatically parses your `Cargo.toml` at runtime to isolate package markers and direct output binary paths.
* **Built-in Guardrails:** Automatically executes your project's test suite inside an Alpine container context *before* compiling production releases.
* **Smart Runtime Sandboxing:** Boots your fresh binary inside an isolated Alpine sandbox with zero port configurations exposed by default—ideal for background processing systems and workers.
* **Strict Offline Mode:** Includes a dedicated `-offline` flag to stop internet verification sweeps and force usage of locally cached images.

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

Since your system environment paths link directly to the repository folder, updating `alprust` to the latest version requires no installer re-runs. Simply pull down the latest changes from GitHub from anywhere:

### 🛠️ On Windows (PowerShell)

```powershell
cd ~\alprust; git pull

```

### 🍏 / 🐧 On macOS or Linux

```bash
cd ~/alprust && git pull

```

---

## Usage & Subcommands

Simply navigate to the root directory of **any** Rust project (the folder containing your `Cargo.toml`) and call your desired action:

### 1. Verification Checking

Validates compilation integrity and tracks architectural warnings inside the Alpine Linux environment without triggering a full build:

```bash
alprust check

```

### 2. Isolated Test Executions

Isolates and fires the full project test suite inside an active Alpine context:

```bash
alprust test

```

### 3. Production Compilation Only

Compiles and extracts the bare-metal binary straight into your local `./output/` folder without launching a live verification container:

```bash
alprust build

```

### 4. Continuous Dev Loop (Default Action)

Runs test workflows, outputs the static binary, and **immediately boots it live** inside an Alpine runtime container instance:

```bash
alprust
# Or explicitly:
alprust run

```

### Advanced Flags Configurations

You can freely append environment tags and override standard behavior across subcommands:

* **`-port <number>`**: Exposes custom network bridges out to your host machine (e.g., `alprust -port 3000`).
* **`-offline`**: Forces Docker to rely exclusively on local target caches (e.g., `alprust check -offline`).

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