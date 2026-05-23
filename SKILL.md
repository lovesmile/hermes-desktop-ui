---
name: hermes-desktop-ui
description: Flutter-based desktop management panel for Hermes Agent — view sessions, skills, models, logs, and manage cron jobs through a GUI
version: 1.0.0
tags: [hermes, desktop, ui, gui, dashboard, management, flutter]
homepage: https://github.com/NousResearch/hermes-desktop-ui
---

# Hermes Desktop UI

A native desktop management panel for Hermes Agent. View your chat history, installed skills, model configuration, cron jobs, and logs — all through a GUI.

## Features

- **📊 Dashboard** — Session stats, skill count, log size, Gateway status
- **💬 Chat History** — Browse past conversations with message history
- **🧠 Models & Skills** — View/switch model config, browse 155+ installed skills
- **🔌 Platform Management** — Configure 8 platforms with step-by-step docs
- **⏰ Cron Jobs** — Visual management with one-click execution, skill association
- **📋 Log Viewer** — Filter by level, search keywords, clear display
- **⚙️ Settings** — Gateway URL config, theme toggle, YAML editor

## Quick Start

### Option 1: Download Pre-built Binary

Download the latest release ZIP from [GitHub Releases](https://github.com/NousResearch/hermes-desktop-ui/releases), extract, and run `hermes_desktop.exe`.

### Option 2: Install via Hermes Skill

```bash
# 1. Enable Gateway API Server
echo 'API_SERVER_ENABLED=true' >> ~/.hermes/.env
hermes gateway restart

# 2. Install skill
hermes skills install https://raw.githubusercontent.com/NousResearch/hermes-desktop-ui/main/SKILL.md

# 3. Build & start
cd ~/.hermes/skills/hermes-desktop-ui
flutter build windows --release
./bin/hermes-desktop-ui start
```

### Option 3: Build from Source

```bash
git clone https://github.com/NousResearch/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release   # Windows
# or
flutter build linux --release     # Linux
```

## Configuration

### Gateway URL (Local or Remote)

**Local:** Default `http://localhost:8642`

**Remote (e.g., Seoul server):** Open Settings → Gateway 地址 → enter `http://<server-ip>:8642`

The app auto-detects `~/.hermes/` from: `$HERMES_HOME` → `$HOME/.hermes` → WSL UNC path → `%USERPROFILE%\.hermes`

## CLI

```bash
hermes-desktop-ui start     # Launch
hermes-desktop-ui build     # Build release
hermes-desktop-ui status    # Check status
```

## Build Requirements

- **Flutter SDK** ≥ 3.0
- **Windows:** Visual Studio 2022 Build Tools (Desktop C++ workload)
- **Linux:** `apt install libgtk-3-dev`

## Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Triggers the GitHub Action to build, package, and publish a release.
