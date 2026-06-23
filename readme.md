# alprust 🚀

`alprust` is a lightweight, zero-footprint CLI tool designed to compile ultra-lean, static Rust binaries targeted specifically for **Alpine Linux bare-metal instances** (ideal for low-resource environments like a 2GB RAM free-tier VPS). 

Created and maintained by **codesbysuman**.

---

## The Problem It Solves

When deploying Rust applications to a minimalist Alpine Linux environment, you must target the lightweight `musl` standard library instead of the traditional `glibc`. 

Trying to set up this cross-compilation toolchain **natively or reliably on Windows or macOS is notoriously frustrating**, often requiring heavy dependencies, complex linker configurations, or broken environment variables. While Docker solves this runtime isolation issue, manually writing, managing, and maintaining custom multi-stage `Dockerfiles` for every single microservice introduces unnecessary friction and clutters your codebase.

**`alprust` completely removes this hassle.** It handles the entire compilation, testing, and runtime emulation pipeline directly in-memory via streamed Docker processing. 

---

## Features

* **Zero Codebase Clutter:** Operates entirely in-memory. It pipes the build instructions straight to the Docker daemon via `stdin`, leaving your local repository clean (no temporary `Dockerfile.dev` files created).
* **Dynamic Configuration:** Automatically reads your `Cargo.toml` at runtime to detect your package name and manage target outputs.
* **Built-in Guardrails:** Automatically executes your project's test suite inside an Alpine container context *before* compiling the production release. If your tests fail, it safely halts the build.
* **Live Sandbox Verification:** Instantly boots your fresh binary inside an isolated Alpine sandbox right after compiling, allowing you to test endpoints (like `/health`) locally on port `8080`.
* **Strict Offline Mode:** Includes a dedicated `-offline` flag to drop internet pings entirely and force usage of locally cached images.

---

## Prerequisites

Before installing, ensure you have **Docker Desktop** installed, running, and accessible via your terminal on your machine.

---

## Quick Start & Installation

Run the explicit one-liner command below for your operating system to clone the repository, navigate into the folder, and execute the installation setup in one shot:

### 🛠️ On Windows (PowerShell)
Ensure your PowerShell execution policy allows running local scripts, then execute this one-liner:
```powershell
git clone [https://github.com/codesbysuman/alprust.git](https://github.com/codesbysuman/alprust.git) && cd alprust && Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force && .\install.ps1

```

*Note: Please close and restart your terminal window after the script finishes to refresh your environment PATH variables.*

### 🍏 / 🐧 On macOS or Linux

Open your terminal and run this one-liner:

```bash
git clone [https://github.com/codesbysuman/alprust.git](https://github.com/codesbysuman/alprust.git) && cd alprust && bash install.sh

```

---

## Usage

Simply navigate to the root directory of **any** Rust project (the folder containing your `Cargo.toml`) and run your preferred execution mode:

### 1. Standard Mode

Validates your tests, cross-compiles your release binary to a local `./output/` folder, and boots the microservice container:

```bash
alprust

```

### 2. Strict Offline Mode

Performs the exact same workflow, but forces Docker to skip checking remote registries for image updates—perfect for offline coding sessions or instant builds:

```bash
alprust -offline

```

### 💡 Testing Network Endpoints Locally

To interact with your server or test a `/health` endpoint while `alprust` is running the sandbox container, ensure your Rust code binds to network address `0.0.0.0` instead of `127.0.0.1`:

```rust
// In your main.rs setup (Axum, Actix, Tokio, etc.)
let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await?;

```

Once booted, open your browser or Postman on your host machine and hit: `http://localhost:8080/health`.

Press **`Ctrl + C`** in your terminal to shut down the server sandbox cleanly. Your production-ready binary will be waiting natively inside your project's new `./output/` directory, ready to be copied directly onto your bare VPS metal.