---
name: hermes-desktop-ui
description: Flutter-based desktop management panel for Hermes Agent — view sessions, skills, models, logs, and manage cron jobs through a GUI
version: 1.0.0
author: Hermes Desktop
tags: [hermes, desktop, ui, gui, dashboard, management, flutter]
homepage: https://github.com/lovesmile/hermes-desktop-ui
---

# Hermes Desktop UI

A native desktop management panel for Hermes Agent. View your chat history, installed skills, model configuration, cron jobs, and logs — all through a GUI instead of the terminal.

## Features

- **📊 Dashboard** — Token usage, session stats, system status
- **💬 Chat History** — Browse past conversations by source (CLI, Telegram, Discord)
- **🧠 Skills** — Browse installed skills with descriptions and versions
- **🔌 Platform Management** — Configure Telegram/Discord/Slack/WhatsApp etc.
- **⏰ Cron Jobs** — Visual management with one-click execution
- **📋 Log Viewer** — Filter by level, search keywords
- **⚙️ Config Editor** — Visual YAML editor for config.yaml
- **🤖 Model Config** — View current model/provider settings

## Requirements

- Hermes Agent installed and running
- Flutter SDK 3.0+ (for building from source)
- API Server enabled (see setup below)

## Quick Start

### 1. Enable the Gateway API Server

Add this to `~/.hermes/.env`:
```
API_SERVER_ENABLED=true
```
Then restart the gateway:
```bash
hermes gateway restart
```

### 2. Install via Hermes Skills

```bash
hermes skills install https://raw.githubusercontent.com/<your-username>/hermes-desktop-ui/main/SKILL.md
```

### 3. Build & Run

```bash
# Clone / enter the project directory
cd ~/.hermes/skills/hermes-desktop-ui/

# Build (requires Flutter SDK)
flutter build windows --release   # Windows
# or
flutter build linux --release     # Linux

# Start
./bin/hermes-desktop-ui start
```

Or directly from the cloned repo:
```bash
git clone https://github.com/<your-username>/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter run -d windows   # or -d linux
```

## CLI Usage

After building, use the launcher script:

```bash
./bin/hermes-desktop-ui start    # Launch the UI
./bin/hermes-desktop-ui build    # Build release
./bin/hermes-desktop-ui status   # Check Gateway + app status
```

Add the `bin/` directory to your PATH for global access:
```bash
export PATH="$HOME/.hermes/skills/hermes-desktop-ui/bin:$PATH"
hermes-desktop-ui start
```

## Architecture

```
Flutter Desktop App
    │
    ├── HTTP/SSE ──→ Hermes Gateway API Server (:8642)
    │                  ├── GET /health
    │                  ├── POST /v1/chat/completions (SSE stream)
    │                  └── POST /v1/runs/*
    │
    └── File I/O ──→ ~/.hermes/config.yaml
                     ~/.hermes/.env
                     ~/.hermes/sessions/
                     ~/.hermes/skills/
                     ~/.hermes/logs/
                     ~/.hermes/auth.json
```

## Project Structure

```
hermes-desktop-ui/
├── SKILL.md              # Hermes Skill metadata (for hermes skills install)
├── bin/
│   └── hermes-desktop-ui # Launch script
├── lib/
│   ├── main.dart         # Entry point
│   ├── config/theme.dart # Material 3 dark theme
│   ├── models/           # Data models
│   ├── services/         # Gateway API + file I/O
│   ├── screens/          # 7 screens
│   └── widgets/          # Reusable components
├── README.md
└── pubspec.yaml
```

## Build from Source

```bash
git clone https://github.com/<your-username>/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release   # or flutter build linux --release
```

The executable will be at `build/windows/x64/release/hermes_desktop.exe`.
