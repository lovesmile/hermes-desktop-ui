# Hermes Desktop UI

A native desktop management panel for [Hermes Agent](https://github.com/NousResearch/hermes-agent). Browse chat history, manage skills, configure platforms, monitor logs, and control cron jobs — all through a GUI.

![GitHub release](https://img.shields.io/github/v/release/NousResearch/hermes-desktop-ui)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-blue)

## Features

| Module | Description |
|--------|-------------|
| **📊 Dashboard** | Session stats, skill count, log size, Gateway status + quick navigation |
| **💬 Chat History** | Browse sessions, read messages, continue conversations |
| **🧠 Models & Skills** | View/switch model config, environment variables, 155+ installed skills |
| **🔌 Platform Management** | Configure Telegram / Discord / Slack / WhatsApp / Feishu / WeCom / Matrix / WeChat |
| **⏰ Cron Jobs** | Visual cron management, one-click execute, skill association |
| **📋 Logs** | Agent / Gateway / Error logs, level filter, keyword search |
| **⚙️ Settings** | Gateway URL config, theme toggle, YAML editor, Gateway restart |

## Quick Start

### Option 1: Download Pre-built Binary

Download the latest `hermes-desktop-ui-windows-v*.zip` from the [Releases page](https://github.com/NousResearch/hermes-desktop-ui/releases), extract, and run `hermes_desktop.exe`.

### Option 2: Install via Hermes Skill

```bash
# Prerequisites: Hermes Gateway running with API server enabled
echo 'API_SERVER_ENABLED=true' >> ~/.hermes/.env
hermes gateway restart

# Install the skill
hermes skills install https://raw.githubusercontent.com/NousResearch/hermes-desktop-ui/main/SKILL.md

# Launch
cd ~/.hermes/skills/hermes-desktop-ui
./bin/hermes-desktop-ui start
```

### Option 3: Build from Source

**Requirements:**
- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.0
- **Windows:** Visual Studio 2022 Build Tools (Desktop development with C++)
- **Linux:** `apt install libgtk-3-dev` (or equivalent)

```bash
git clone https://github.com/NousResearch/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release   # or: flutter build linux --release
```

The executable will be at:
- **Windows:** `build\windows\x64\runner\Release\hermes_desktop.exe`
- **Linux:** `build/linux/x64/release/hermes_desktop`

## CLI Usage

```bash
hermes-desktop-ui start     # Launch the desktop UI
hermes-desktop-ui build     # Build release binary
hermes-desktop-ui status    # Check Gateway + app status
```

## Configuration

### Connecting to Hermes (Local or Remote)

The app connects to Hermes Agent via **Gateway API** (`/health`, `/v1/chat/completions`) and reads **filesystem** (`~/.hermes/`).

**Default:** `http://localhost:8642` (local Hermes Gateway)

**Remote setup (e.g., Seoul server):**
1. Open Settings → Gateway 设置
2. Click "Gateway 地址" and enter `http://<server-ip>:8642`
3. Save → restart app

Configuration is stored in `~/.hermes/desktop_config.json`.

### Auto-detected Paths

The app finds `~/.hermes/` in this order:
1. `HERMES_HOME` environment variable
2. `$HOME/.hermes` (WSL path)
3. `\\wsl.localhost\Ubuntu\home\tian\.hermes` (Windows → WSL)
4. `%USERPROFILE%\.hermes` (Windows native)

## Architecture

```
Flutter Desktop App
    │
    ├── HTTP/SSE ──→ Hermes Gateway API Server (:8642)
    │                  ├── GET /health
    │                  ├── POST /v1/chat/completions (SSE)
    │                  └── POST /v1/runs/
    │
    └── File I/O ──→ ~/.hermes/
                       ├── config.yaml          # Model config
                       ├── .env                 # Environment variables
                       ├── sessions/            # Chat history (JSON)
                       ├── skills/              # Installed skills
                       ├── logs/                # Log files
                       ├── desktop_config.json  # Desktop UI settings
                       └── auth.json            # API credentials
```

## Project Structure

```
hermes-desktop-ui/
├── .github/workflows/release.yml   # GitHub Actions release pipeline
├── SKILL.md                        # Hermes Skill metadata
├── bin/hermes-desktop-ui           # CLI launcher script
├── lib/
│   ├── main.dart                   # Entry point + navigation
│   ├── config/theme.dart           # Dark/light theme definitions
│   ├── models/                     # 5 data models
│   ├── services/                   # Gateway API + file I/O
│   ├── screens/                    # 7 feature pages
│   └── widgets/                    # Reusable components
├── pubspec.yaml
└── README.md
```

## Publishing a Release

```bash
# Tag and push to trigger the release workflow
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Action will:
1. Build `flutter build windows --release`
2. Package the exe + assets into a ZIP
3. Create a GitHub Release with the zip attached

## Data Sources

| Data | Source |
|------|--------|
| Chat sessions | `~/.hermes/sessions/session_*.json` |
| Skills list | `~/.hermes/skills/**/SKILL.md` |
| Model config | `~/.hermes/config.yaml` |
| Environment vars | `~/.hermes/.env` |
| Logs | `~/.hermes/logs/*.log` |
| Platform config | Parsed from `config.yaml` |
| Live chat | Gateway API Server (configured URL) |

## License

MIT
