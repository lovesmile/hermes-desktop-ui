# Hermes Desktop UI

**Hermes Agent 的可视化桌面客户端** — 像微信/Telegram 一样管理多个 AI 会话，并行不冲突。

![GitHub release](https://img.shields.io/github/v/release/lovesmile/hermes-desktop-ui)
![Platform](https://img.shields.io/badge/platform-Windows-blue)

---

## 特色

| 特性 | 说明 |
|------|------|
| **🎯 并行会话** | 多个会话同时进行，AI 回复互不干扰。会话A写代码、会话B查资料，切换查看各自进度 |
| **📦 本地数据库** | 会话和消息存在 `desktop_db.json`，重启不丢。发消息即时存盘，崩溃也不丢 |
| **🔄 流式并行** | 切换会话不中断 AI 回复。后台继续接收，切回看到完整内容 |
| **🖥️ 轻量客户端** | 一个 exe 搞定，依赖 Hermes 服务端做 AI 计算 |
| **🌐 远程连接** | 支持连接远程 Hermes Gateway（如云服务器），本地无需 GPU |
| **🔧 开箱配置** | 首次启动弹出配置向导，填 Gateway 地址 + API Key 即可 |

---

## 架构

```
┌─────────────────────┐         HTTP/SSE          ┌─────────────────────┐
│   Desktop App       │ ──────────────────────▶    │  Hermes Gateway     │
│   (Flutter/Windows) │ ◀──────────────────────    │  (Python/aiohttp)   │
│                     │    POST /v1/chat/          │                     │
│  ┌───────────────┐  │    completions (SSE)       │  ┌───────────────┐  │
│  │ LocalDatabase  │  │                            │  │ AI Engine     │  │
│  │ desktop_db.json│  │                            │  │ (LLM calls)   │  │
│  │  ─ 会话 + 消息 │  │                            │  └───────────────┘  │
│  └───────────────┘  │                            └─────────────────────┘
│         ▲           │
│         │ 本地读写   │
│         ▼           │
│  ┌───────────────┐  │
│  │ Flutter UI    │  │
│  │ 仪表盘/聊天/   │  │
│  │ 模型/设置...   │  │
│  └───────────────┘  │
└─────────────────────┘
```

**核心设计：客户端只管界面和本地存储，服务端只管 AI 计算。**

---

## 完整功能

| 模块 | 功能 |
|------|------|
| **📊 仪表盘** | 总会话数、已装技能、日志大小、Gateway 状态 + 快捷导航 |
| **💬 聊天** | 多会话并行流式聊天、每条消息即时存本地、会话切换 AI 不中断 |
| **🧠 模型与技能** | 15 个 Provider（deepseek→xiaomi）、切换模型自动填充 Base URL、技能列表 |
| **🔌 平台管理** | Telegram / Discord / Slack / WhatsApp / 飞书 / 企业微信 / Matrix / 微信 |
| **⏰ 定时任务** | 可视化 cron 管理（预留 UI） |
| **📋 日志** | Agent / Gateway / Error 日志、级别过滤、关键词搜索 |
| **⚙️ 设置** | Gateway 地址、API Key、主题切换、config.yaml 编辑、.env 编辑、重启 Gateway |

---

## 安装

### 前置条件：Hermes 服务端

Desktop App 是客户端，需要 Hermes Agent 服务端提供 AI 能力。

**本地运行：**
```bash
# 1. 安装 Hermes Agent（如果还没装）
pip install hermes-agent

# 2. 配置 API Key
hermes setup

# 3. 启用 Gateway API Server
echo 'API_SERVER_ENABLED=true' >> ~/.hermes/.env
echo 'API_SERVER_KEY=your-secret-key' >> ~/.hermes/.env   # ← 客户端需要这个来认证

# 4. 重启 Gateway
hermes gateway restart
```

**远程服务器（如云 VPS）：**
同上步骤，但 Gateway 地址用服务器 IP。确保服务器防火墙放行 8642 端口。

### 客户端安装

**方式一：下载预编译 exe**

从 [Releases 页面](https://github.com/lovesmile/hermes-desktop-ui/releases) 下载 `hermes-desktop-ui-v*.zip`，解压运行 `hermes_desktop.exe`。

首次启动会自动弹出配置向导，填入：
- **Gateway 地址**：`http://localhost:8642`（本地）或 `http://服务器IP:8642`（远程）
- **API Key**：和 `.env` 中 `API_SERVER_KEY` 的值一致

**方式二：源码编译**

```bash
# 环境要求
# - Flutter SDK ≥ 3.0
# - Windows: Visual Studio 2022 Build Tools (Desktop development with C++)

git clone https://github.com/lovesmile/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release
```

编译产物：`build\windows\x64\runner\Release\hermes_desktop.exe`

---

## 配置

### 配置文件

| 文件 | 用途 |
|------|------|
| `~/.hermes/desktop_config.json` | 客户端配置（Gateway 地址、API Key） |
| `~/.hermes/desktop_db.json` | 本地数据库（所有会话和消息） |
| `~/.hermes/config.yaml` | Hermes 主配置 |
| `~/.hermes/.env` | 环境变量（API Key 等） |

客户端配置在**设置页**可直接修改：
- Gateway 地址 → 设置 → Gateway 设置 → Gateway 地址
- API Key → 设置 → Gateway 设置 → API Key
- config.yaml → 设置 → 配置文件 → 编辑 config.yaml
- .env → 设置 → 配置文件 → 编辑 .env

### Provider 支持

切换模型时可选 15 个 Provider，自动填充默认 Base URL：

| Provider | 默认模型 | Base URL |
|----------|---------|----------|
| deepseek | v4-flash, v3, r1 | `https://api.deepseek.com/v1` |
| openrouter | claude-sonnet-4, gpt-4o... | `https://openrouter.ai/api/v1` |
| anthropic | claude-sonnet-4, opus-4 | `https://api.anthropic.com/v1` |
| openai | gpt-4o, gpt-4o-mini, o3 | `https://api.openai.com/v1` |
| gemini | gemini-2.5-pro, flash | `https://generativelanguage.googleapis.com/v1beta/openai` |
| kimi | kimi-k2.5 | `https://api.moonshot.cn/v1` |
| ollama | llama-3.3-70b, qwen-2.5 | `https://ollama.com/v1` |
| glm | glm-4-plus, glm-4-air | `https://api.z.ai/api/paas/v4` |
| minimax | minimax-m2.5 | `https://api.minimax.io/v1` |
| arcee | trinity-mini, large | `https://api.arcee.ai/v1` |
| opencode-zen | gpt-4o, claude-sonnet-4 | `https://opencode.ai/zen/v1` |
| opencode-go | glm-5, kimi-k2.5 | `https://opencode.ai/zen/go/v1` |
| huggingface | Llama-4, Mistral-Large | `https://api-inference.huggingface.co/v1` |
| qwen | qwen-max, qwen-plus | `https://portal.qwen.ai/v1` |
| xiaomi | mimo-v2-pro, flash, omni | `https://api.xiaomimimo.com/v1` |

---

## 本地数据库结构

`desktop_db.json` 由客户端自行管理，与 Hermes 服务端无关：

```json
{
  "version": 1,
  "sessions": {
    "20260523_191530_abc123": {
      "id": "20260523_191530_abc123",
      "title": "05/23 帮我写个爬虫",
      "source": "cli",
      "created_at": "2026-05-23T19:15:30.000Z",
      "updated_at": "2026-05-23T19:16:45.000Z",
      "messages": [
        {"role": "user", "content": "帮我写个爬虫", "timestamp": "..."},
        {"role": "assistant", "content": "好的，这里是一个...", "timestamp": "..."}
      ]
    }
  }
}
```

消息在发送前即写入磁盘，崩溃场景不丢数据。

---

## 构建 Release

```bash
# 打标签触发 GitHub Actions 自动构建
git tag v1.0.0
git push origin v1.0.0
```

Actions 会自动：
1. `flutter build windows --release`
2. 打包 exe + 依赖 DLL 为 ZIP
3. 上传到 GitHub Release

---

## 技术栈

| 层 | 技术 |
|----|------|
| 桌面 UI | Flutter 3.x / Material Design 3 |
| 本地存储 | JSON 文件（`desktop_db.json`） |
| 网络通信 | HTTP + SSE（Server-Sent Events） |
| 认证 | Bearer token + API_SERVER_KEY |
| 构建 | GitHub Actions / MSBuild |
| 服务端 | Hermes Agent Gateway API |

---

## License

MIT
