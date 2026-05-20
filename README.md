# Hermes Desktop UI

A native desktop management panel for [Hermes Agent](https://github.com/NousResearch/hermes-agent). View your chat history, installed skills, model configuration, cron jobs, and logs — all through a GUI instead of the terminal.

## Features

| 模块 | 说明 |
|------|------|
| **📊 仪表盘** | 会话统计、技能数量、日志大小、Gateway 状态 |
| **💬 会话历史** | 浏览 ~/.hermes/sessions/ 中的对话记录，按来源分组 |
| **🧠 模型与技能** | 查看当前模型配置、环境变量、已安装技能列表（带版本） |
| **🔌 平台管理** | 配置 Telegram/Discord/Slack/WhatsApp 等 8 个平台 |
| **⏰ 定时任务** | 可视化管理 Cron 任务，一键执行 |
| **📋 日志查看** | Agent/Gateway/错误日志，级别过滤，关键词搜索 |
| **⚙️ 设置** | 可视化 YAML 编辑器、Gateway 控制 |

## Quick Start

### 1. 开启 API Server

```bash
echo 'API_SERVER_ENABLED=true' >> ~/.hermes/.env
hermes gateway restart
```

### 2. 安装

```bash
hermes skills install https://raw.githubusercontent.com/<your-username>/hermes-desktop-ui/main/SKILL.md
```

或通过 tap：
```bash
hermes skills tap add <your-username>/hermes-desktop-ui
hermes skills install hermes-desktop-ui
```

### 3. 构建 & 启动

**Windows:**
```powershell
cd C:\Users\<you>\projects\hermes-desktop-ui
flutter pub get
flutter build windows --release
.\bin\hermes-desktop-ui start
```

**Linux:**
```bash
cd ~/.hermes/skills/hermes-desktop-ui
flutter pub get
flutter build linux --release
./bin/hermes-desktop-ui start
```

## CLI Usage

```bash
hermes-desktop-ui start     # 启动桌面管理面板
hermes-desktop-ui build     # 编译 release 版本
hermes-desktop-ui status    # 检查 Gateway + 应用状态
```

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
                       ├── config.yaml      # 模型配置
                       ├── .env             # 环境变量
                       ├── sessions/        # 会话历史
                       ├── skills/          # 已安装技能
                       ├── logs/            # 日志文件
                       └── auth.json        # API 凭证
```

## Project Structure

```
hermes-desktop-ui/
├── SKILL.md               # Hermes Skill 元数据
├── bin/
│   └── hermes-desktop-ui  # CLI 启动脚本
├── lib/
│   ├── main.dart
│   ├── config/theme.dart
│   ├── models/            # 5 个数据模型
│   ├── services/          # Gateway API + 文件 I/O
│   ├── screens/           # 7 个功能页面
│   └── widgets/           # 可复用组件
├── pubspec.yaml
└── README.md
```

## Build Requirements

- **Flutter SDK** ≥ 3.0
- **Windows:** Visual Studio 2022 Build Tools (Desktop development with C++)
- **Linux:** GTK 3.0+ development headers (`apt install libgtk-3-dev`)

## Data Sources

The app reads real Hermes data directly from:

| 数据 | 来源 |
|------|------|
| 会话历史 | `~/.hermes/sessions/*.jsonl` |
| 技能列表 | `~/.hermes/skills/**/SKILL.md` |
| 模型配置 | `~/.hermes/config.yaml` |
| 环境变量 | `~/.hermes/.env` |
| 日志 | `~/.hermes/logs/*.log` |
| 平台配置 | `~/.hermes/config.yaml` 解析 |
| 实时聊天 | Gateway API Server (`localhost:8642`) |

## License

MIT
