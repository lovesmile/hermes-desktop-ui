---
name: hermes-desktop-ui
description: Flutter-based desktop management panel for Hermes Agent — view sessions, skills, models, logs, cron, and platform config through a GUI
version: 1.0.4
tags: [hermes, desktop, ui, gui, dashboard, management, flutter]
homepage: https://github.com/lovesmile/hermes-desktop-ui
---

# Hermes Desktop UI

A native Windows desktop management panel for Hermes Agent. Supports three connection modes (local WSL / embedded Windows / remote SSH) through a unified interface.

## Features

- **📊 Dashboard** — Stats cards, quick navigation to all pages
- **💬 Chat** — Multi-session parallel streaming chat, session management with remarks
- **⏰ Cron Jobs** — Visual management with one-click execution
- **🧠 Models & Skills** — 15 providers, model config with auto-restart
- **📂 File Browser** — Browse and preview files through Gateway API
- **🔌 Platform Management** — 12 platform integrations
- **📋 Log Viewer** — Filter by level, search keywords
- **⚙️ Settings** — Mode switch, SSH config, YAML editor

## Quick Start

### Option 1: Download Pre-built Binary

Download from [GitHub Releases](https://github.com/lovesmile/hermes-desktop-ui/releases), extract, and run `hermes_desktop.exe`.

### Option 2: Build from Source

```bash
git clone https://github.com/lovesmile/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release
```

## Architecture

Three connection modes managed by `ConnectionManager`:

- **Local (WSL)**: `WslBridge` — wsl.exe bash execution
- **Embedded**: `EmbeddedBridge` — Windows native hermes.exe
- **Remote (SSH)**: `RemoteBridge` — SSH tunnel + remote commands

All upper layers call `ConnectionManager.runShell()` — no mode branching in business code.

## Configuration

Config files at `~/.hermes/`:

- `desktop_config.json` — Client settings
- `desktop_db*.json` — Local session database
- `config.yaml` — Hermes model/provider config
- `.env` — Environment variables (API keys)

## Build Requirements

- **Flutter SDK** ≥ 3.0
- **Windows:** Visual Studio 2022 Build Tools (Desktop C++ workload)

## Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Triggers GitHub Action to build, package, and publish.
