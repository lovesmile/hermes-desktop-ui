# Hermes Desktop UI

**Hermes Agent 的可视化桌面客户端** — 像微信/Telegram 一样管理多个 AI 会话，并行不冲突。

![GitHub release](https://img.shields.io/github/v/release/lovesmile/hermes-desktop-ui)
![Platform](https://img.shields.io/badge/platform-Windows-blue)

---

## 特色

| 特性              | 说明                                                                          |
| ----------------- | ----------------------------------------------------------------------------- |
| **🎯 并行会话**   | 多个会话同时进行，AI 回复互不干扰。会话A写代码、会话B查资料，切换查看各自进度 |
| **📦 本地数据库** | 会话和消息存在 `desktop_db.json`，重启不丢。发消息即时存盘，崩溃也不丢        |
| **🔄 流式并行**   | 切换会话不中断 AI 回复。后台继续接收，切回看到完整内容                        |
| **🖥️ 轻量客户端** | 一个 exe 搞定，依赖 Hermes 服务端做 AI 计算                                   |
| **🌐 远程连接**   | 支持连接远程 Hermes Gateway（如云服务器），本地无需 GPU                       |
| **🗄️ 内嵌模式**   | Windows 下直接运行内置 hermes 可执行文件，无需 WSL                            |
| **🔧 开箱配置**   | 首次启动弹出配置向导，填 Gateway 地址 + API Key 即可                          |
| **📂 文件浏览**   | 通过 Gateway API 浏览 Hermes outputs 目录，支持文本文件预览                   |
| **🖇️ 连接状态栏** | 顶部状态条实时显示 Gateway 连接状态（本地/远程/离线）                         |

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Hermes Desktop App                       │
│                     (Flutter/Windows)                       │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                ConnectionManager                     │   │
│  │  ┌──────────────────┐    ┌──────────────────────┐    ┌───────────────────┐   │   │
│  │  │  本地模式 (Local)  │    │  远程模式 (Remote)    │    │  内嵌模式 (Embedded)│   │   │
│  │  │  localhost:<port> │    │  ssh -L tunnel →     │    │  hermes.exe 直连   │   │   │
│  │  │  直接连 Gateway   │    │  localhost:<port>     │    │  (无需 WSL)        │   │   │
│  │  └──────────────────┘    └──────────────────────┘    └───────────────────┘   │   │
│  │         │                        ▲                  │   │
│  │         ▼                        │ SSH tunnel       │   │
│  │  ┌────────────────────────────────────┐             │   │
│  │  │        GatewayService (HTTP)       │             │   │
│  │  │  ┌──────────────────────────────┐  │             │   │
│  │  │  │ GET  /health                 │  │             │   │
│  │  │  │ POST /v1/chat/completions    │  │             │   │
│  │  │  │      (SSE streaming)         │  │             │   │
│  │  │  │ GET  /api/status             │  │             │   │
│  │  │  │ GET  /api/status/tokens      │  │             │   │
│  │  │  │ GET  /api/skills             │  │             │   │
│  │  │  │ GET  /api/sessions           │  │             │   │
│  │  │  │ GET  /api/files?path=...     │  │             │   │
│  │  │  │ GET  /api/files/content?...  │  │             │   │
│  │  │  │ GET  /api/logs               │  │             │   │
│  │  │  │ GET  /api/config             │  │             │   │
│  │  │  │ GET  /api/cron               │  │             │   │
│  │  │  │ POST /gateway/restart        │  │             │   │
│  │  │  └──────────────────────────────┘  │             │   │
│  │  └────────────────────────────────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   Screen Layers                      │   │
│  │  ┌──────────┐  ┌──────┐  ┌──────────┐  ┌─────────┐  │   │
│  │  │ 仪表盘    │  │ 聊天  │  │ 平台     │  │ 定时    │  │   │
│  │  │ (Dashboard)│  │(Chat)│  │(Platforms)│  │(Cron)  │  │   │
│  │  └──────────┘  └──────┘  └──────────┘  └─────────┘  │   │
│  │  ┌──────────┐  ┌──────┐  ┌──────────┐  ┌─────────┐  │   │
│  │  │ 日志     │  │ 模型  │  │ 文件     │  │ 设置    │  │   │
│  │  │ (Logs)  │  │ &技能 │  │ (Files)  │  │(Settings)│  │   │
│  │  └──────────┘  └──────┘  └──────────┘  └─────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Connection Status Bar (顶部)              │   │
│  │  ● 已连接 → 本地模式 / 远程: user@host / 内嵌模式    │   │
│  │  ● 未连接 → 红色指示灯 + "未连接"                    │   │
│  │  ● 连接中 → 橙色指示灯 + "连接中..."                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Local Storage Layer                     │   │
│  │  ┌──────────────────┐  ┌──────────────────────┐    │   │
│  │  │ desktop_config   │  │ desktop_db.json      │    │   │
│  │  │ .json            │  │ (会话 + 消息)         │    │   │
│  │  └──────────────────┘  └──────────────────────┘    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/SSE (Bearer Auth)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Hermes Gateway (服务端)                      │
│                 (Python / aiohttp)                          │
│                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │  API Server   │  │  AI Engine    │  │  Skills       │   │
│  │  (端口 8642)  │  │  (LLM calls)  │  │  Plugin System│   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**核心设计：客户端只管界面和本地存储，GatewayService 通过 ConnectionManager 统一管理到服务端的连接。**

---

## 连接模式

Hermes Desktop 支持三种连接模式，由 `ConnectionManager` 统一管理。所有 HTTP 请求都经过同一个 `localhost:<port>` 地址，区别在于后端的连通方式。

### 本地模式 (Local)

- **适用场景**：Hermes Gateway 运行在本机
- **原理**：直接连接 `http://localhost:8642`
- **配置**：无需额外配置，只需填入 Gateway 地址和 API Key
- **健康检查**：每 10 秒检测 `/health` 端点

### 内嵌模式 (Embedded)

- **适用场景**：Windows 用户不想装 WSL，直接使用内置 hermes
- **原理**：在 Windows 上直接运行绑定的 `hermes.exe`，通过 cmd 执行 shell 操作
- **配置**：首次启动会下载 hermes 安装包并解压到 `~/.hermes-desktop/hermes/`
- **优势**：无需 WSL、无需 Linux 环境，开箱即用
- **注意**：部分高级功能（如 SSH 隧道）仅在其他模式下可用

### 远程模式 (Remote/SSH)

- **适用场景**：Hermes Gateway 运行在远程服务器（如云 VPS），本地无 GPU
- **原理**：通过 `ssh -L` 端口转发，将远程服务器的 8642 端口映射到本地
  ```
  ssh -L <local_port>:localhost:8642 user@host
  ```
- **配置**：需要填写 SSH 主机地址、用户名、端口（默认 22）、密钥路径
- **测试连接**：设置页支持一键测试 SSH 连通性
- **自动重连**：每 10 秒健康检查，断开后标记错误状态
- **安全**：支持密钥认证 (`-i`)，支持 `StrictHostKeyChecking=accept-new`

---

## 完整功能

| 模块              | 功能                                                                                                                                                                                                   |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **📊 仪表盘**     | 4 个统计卡片（总会话数、已装技能、日志大小、Gateway 状态）+ 机器状态卡片（CPU/内存/磁盘/运行时间）+ 令牌用量（今日/本月请求）+ 模型配置 + 快捷导航                                                     |
| **💬 聊天**       | 多会话并行流式聊天（SSE）、会话管理（加载/删除/重命名）、技能建议、右键调用技能、每条消息写入本地 DB、切换会话 AI 不中断                                                                               |
| **🧠 模型与技能** | 15 个 Provider（deepseek→xiaomi）、切换模型自动填充 Base URL、技能列表 + 右键快捷调用                                                                                                                  |
| **🔌 平台管理**   | Telegram / Discord / Slack / WhatsApp / 飞书 / 企业微信 / Matrix / 微信                                                                                                                                |
| **⏰ 定时任务**   | 可视化 cron 管理（创建/编辑/删除/立即执行）                                                                                                                                                            |
| **📋 日志**       | Agent / Gateway / Error 日志、级别过滤（INFO/WARN/ERROR/DEBUG）、关键词搜索                                                                                                                            |
| **📂 文件**       | 浏览 ~/.hermes/outputs/ 目录，目录导航、文本文件预览（底部面板 + 复制）、文件信息弹窗                                                                                                                  |
| **⚙️ 设置**       | 连接模式选择（本地/内嵌/远程）、SSH 配置（主机/端口/用户/密钥）、端口覆盖、Gateway 地址、API Key、主题切换、config.yaml 编辑（保存并重启 Gateway）、.env 编辑、重启 Gateway、使用文档（Markdown 渲染） |

### 新特性详解

**连接管理**:

- `ConnectionManager` 单例管理所有连接状态
- 支持本地直连（WSL）、内嵌（Windows 原生）和远程 SSH 隧道三种模式
- 定时健康检查（每 10 秒），状态变更实时通知 UI
- 连接状态栏：应用顶部显示当前连接状态（绿色=已连接、橙色=连接中、红色=未连接）

**Gateway API 覆盖**:

- `/health` — 健康检查
- `/v1/chat/completions` — SSE 流式聊天
- `/api/status` — 机器状态（CPU/内存/磁盘/uptime）
- `/api/status/tokens` — 令牌统计（今日/本月）
- `/api/skills` — 技能列表
- `/api/sessions` — 会话管理
- `/api/files?path=...` — 目录列表
- `/api/files/content?path=...` — 文件内容读取
- `/api/logs` — 日志读取
- `/api/config` — 配置读取/写入
- `/api/cron` — 定时任务管理
- `/gateway/restart` — 重启 Gateway

**文件浏览**:

- 通过 Gateway API 浏览 `~/.hermes/outputs/` 目录
- 目录导航（进入/返回上级/回到根目录）
- 文本文件语法高亮预览（底部面板）
- 文件大小、修改时间显示
- 复制文件内容到剪贴板

**设置增强**:

- 连接模式选择器（本地/内嵌/远程 Radio 卡片）
- SSH 远程配置表单（主机/端口/用户/密钥路径）
- SSH 连接测试按钮
- 端口覆盖设置
- 内嵌使用文档（Markdown 渲染，从 `assets/support_docs.md` 加载）

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

| 文件                            | 用途                                                    |
| ------------------------------- | ------------------------------------------------------- |
| `~/.hermes/desktop_config.json` | 客户端配置（Gateway 地址、API Key、连接模式、SSH 配置） |
| `~/.hermes/desktop_db.json`     | 本地数据库（所有会话和消息）                            |
| `~/.hermes/config.yaml`         | Hermes 主配置                                           |
| `~/.hermes/.env`                | 环境变量（API Key 等）                                  |

客户端配置在**设置页**可直接修改：

- Gateway 地址 → 设置 → Gateway 设置 → Gateway 地址
- API Key → 设置 → Gateway 设置 → API Key
- 连接模式 → 设置 → 连接模式（本地/内嵌/远程）
- SSH 配置 → 设置 → SSH 远程配置（远程模式下显示）
- config.yaml → 设置 → 配置文件 → 编辑 config.yaml
- .env → 设置 → 配置文件 → 编辑 .env

### Provider 支持

切换模型时可选 15 个 Provider，自动填充默认 Base URL：

| Provider     | 默认模型                   | Base URL                                                  |
| ------------ | -------------------------- | --------------------------------------------------------- |
| deepseek     | v4-flash, v3, r1           | `https://api.deepseek.com/v1`                             |
| openrouter   | claude-sonnet-4, gpt-4o... | `https://openrouter.ai/api/v1`                            |
| anthropic    | claude-sonnet-4, opus-4    | `https://api.anthropic.com/v1`                            |
| openai       | gpt-4o, gpt-4o-mini, o3    | `https://api.openai.com/v1`                               |
| gemini       | gemini-2.5-pro, flash      | `https://generativelanguage.googleapis.com/v1beta/openai` |
| kimi         | kimi-k2.5                  | `https://api.moonshot.cn/v1`                              |
| ollama       | llama-3.3-70b, qwen-2.5    | `https://ollama.com/v1`                                   |
| glm          | glm-4-plus, glm-4-air      | `https://api.z.ai/api/paas/v4`                            |
| minimax      | minimax-m2.5               | `https://api.minimax.io/v1`                               |
| arcee        | trinity-mini, large        | `https://api.arcee.ai/v1`                                 |
| opencode-zen | gpt-4o, claude-sonnet-4    | `https://opencode.ai/zen/v1`                              |
| opencode-go  | glm-5, kimi-k2.5           | `https://opencode.ai/zen/go/v1`                           |
| huggingface  | Llama-4, Mistral-Large     | `https://api-inference.huggingface.co/v1`                 |
| qwen         | qwen-max, qwen-plus        | `https://portal.qwen.ai/v1`                               |
| xiaomi       | mimo-v2-pro, flash, omni   | `https://api.xiaomimimo.com/v1`                           |

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
        { "role": "user", "content": "帮我写个爬虫", "timestamp": "..." },
        {
          "role": "assistant",
          "content": "好的，这里是一个...",
          "timestamp": "..."
        }
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

### 本地手动构建

```bash
# 环境要求
# - Flutter SDK ≥ 3.0
# - Windows: Visual Studio 2022 Build Tools (Desktop development with C++)
# - Git

git clone https://github.com/lovesmile/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release
```

编译产物：`build\windows\x64\runner\Release\hermes_desktop.exe`

---

## 技术栈

| 层       | 技术                                                   |
| -------- | ------------------------------------------------------ |
| 桌面 UI  | Flutter 3.x / Material Design 3                        |
| 本地存储 | JSON 文件（`desktop_db.json` + `desktop_config.json`） |
| 网络通信 | HTTP + SSE（Server-Sent Events）                       |
| 连接管理 | SSH 隧道（`ssh -L`）+ 定时健康检查                     |
| 认证     | Bearer token + API_SERVER_KEY                          |
| 构建     | GitHub Actions / MSBuild                               |
| 服务端   | Hermes Agent Gateway API                               |
| Markdown | flutter_markdown（设置页使用文档）                     |

---

## License

MIT

---

## Bridge Architecture (Connection Isolation)

Current runtime uses a unified Environment Bridge architecture:

- Core interface: `HermesBridge`
- Implementations: `WslBridge`, `RemoteBridge`, `EmbeddedBridge`
- Unified entry in upper layer: `ConnectionManager.runShell(...)`

Upper-layer screens/services do not branch on connection mode for shell/file operations.
Mode-specific behavior is isolated in bridge implementations.

Related usage details:

- See `docs/USAGE.md` for first-launch flow, mode switching, data isolation, and troubleshooting.
