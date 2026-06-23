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

* **Zero Codebase Clutter:** Operates entirely in-memory. It pipes the build instructions straight to the Docker daemon via `stdin`, leaving your local repository clean (no temporary files created).
* **Dynamic Configuration:** Automatically reads your `Cargo.toml` at runtime to detect your package name and manage target outputs.
* **Built-in Guardrails:** Automatically executes your project's test suite inside an Alpine container context *before* compiling the production release. If your tests fail, it safely halts the build.
* **Smart Runtime Sandboxing (Zero-Port Default):** Boots your binary without opening local network ports by default. This makes it perfect for background task workers or queue engines and prevents local port collisions.
* **Dynamic Port Forwarding:** Easily expose custom ports using the `-port` flag when building web applications.
* **Strict Offline Mode:** Includes a dedicated `-offline` flag to drop internet pings entirely and force usage of locally cached images.

---

## Prerequisites

Before installing, ensure you have **Docker Desktop** installed, running, and accessible via your terminal on your machine.

---

## Quick Start & Installation

Run the explicit command below for your operating system to clone the repository, navigate into the folder, and execute the installation setup in one shot:

### 🛠️ On Windows (PowerShell)

Ensure your PowerShell execution policy allows running local scripts, then execute this command:

```powershell
git clone https://github.com/codesbysuman/alprust.git; cd alprust; Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force; .\install.ps1

```

*Note: Please close and restart your terminal window after the script finishes to refresh your environment PATH variables.*

### 🍏 / 🐧 On macOS or Linux

Open your terminal and run this command:

```bash
git clone https://github.com/codesbysuman/alprust.git && cd alprust && bash install.sh

```

---

## Usage

Simply navigate to the root directory of **any** Rust project (the folder containing your `Cargo.toml`) and run your preferred execution mode:

### 1. Worker / Engine Mode (Default)

Compiles your project and launches it as a background process with no open network ports (ideal for queue workers or tasks engines):

```bash
alprust

```

### 2. Web Server Mode (Custom Port Binding)

If your app is an API or microservice requiring network communication, pass a custom `-port` argument to map that port directly out to your host machine:

```bash
alprust -port 3000

```

### 3. Strict Offline Mode

Performs the build strictly from your local image storage layout, eliminating network dependency overhead entirely:

```bash
alprust -offline

```

*Note: You can combine flags freely, for example: `alprust -offline -port 8080*`

---

## 💡 Testing Network Endpoints Locally

If you are using **Web Server Mode** and want to interact with your server or test a `/health` endpoint while `alprust` is running the sandbox container, ensure your Rust code binds to network address `0.0.0.0` instead of `127.0.0.1`:

```rust
// In your main.rs setup (Axum, Actix, Tokio, etc.)
let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;

```

Once booted via `alprust -port 8080`, open your browser or Postman on your host machine and hit: `http://localhost:8080/health`.

Press **`Ctrl + C`** in your terminal to shut down the runtime sandbox cleanly. Your production-ready binary will be waiting natively inside your project's new `./output/` directory, ready to be copied directly onto your bare VPS metal.