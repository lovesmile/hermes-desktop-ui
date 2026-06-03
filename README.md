# Hermes Desktop UI

**Hermes Agent 的可视化桌面客户端** — 像微信一样管理多个 AI 会话，并行不冲突。

![GitHub release](https://img.shields.io/github/v/release/lovesmile/hermes-desktop-ui)
![Platform](https://img.shields.io/badge/platform-Windows-blue)

---

## 特色

| 特性                    | 说明                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| **🎯 并行会话**         | 多个会话同时进行，AI 回复互不干扰。会话 A 写代码、会话 B 查资料，切换查看各自进度               |
| **📦 消息即时存盘**     | 发消息即写入本地 JSON 数据库，崩溃不丢。AI 回复流完成后自动持久化                                |
| **🔄 流式并行**         | 切换会话不中断 AI 回复。后台继续接收 SSE 流，切回看到完整内容                                    |
| **🔗 会话续聊**         | Gateway session ID 存本地数据库，重启应用后选中会话继续聊，上下文不丢失                          |
| **📐 长回复自动分段**   | AI 回复超过 2000 字自动切为多条消息气泡，防止渲染超长文本卡死                                   |
| **🖥️ 三种模式**         | 本地 WSL、内嵌 Windows 原生、远程 SSH 三种连接模式，统一接口切换                                 |
| **🔧 开箱即用**         | 内嵌模式自带 hermes.exe，首次启动自动下载，无需 WSL 或 Linux                                    |
| **🌐 远程 SSH 连接**    | SSH 隧道连接远程 Hermes Gateway，本地无需 GPU 或 Hermes 安装                                    |
| **🖇️ 状态栏实时显示**   | 顶部状态条实时显示 Gateway 连接状态（本地/远程/内嵌/离线/连接中）                                |
| **🎨 主题定制**         | 6 种主题色（科技蓝/翡翠绿/罗兰紫/玫瑰红/暖橙/青色）+ 深色/浅色模式一键切换                       |
| **📂 文件浏览**         | 通过 Gateway API 浏览 Hermes outputs 目录，支持文本文件预览                                     |
| **🔋 资源占用低**       | UI 更新节流（300ms）+ 流式内容分段，长时间 AI 任务后锁屏唤醒不卡死                              |
| **🔒 单实例保护**       | TCP 端口锁防止多开，独占资源                                                                    |

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Hermes Desktop App                       │
│                     (Flutter/Windows)                       │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                ConnectionManager                     │   │
│  │  ┌────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │  │ 本地 (WSL)      │  │ 远程 (SSH)       │  │ 内嵌 (Win)   │  │
│  │  │ localhost:8642  │  │ ssh -L tunnel →  │  │ hermes.exe   │  │
│  │  │ 直接连 Gateway  │  │ localhost:<port> │  │ 自带运行     │  │
│  │  └────────────────┘  └──────────────────┘  └──────────────┘  │
│  │         │                    ▲                  │             │
│  │         ▼                    │ SSH tunnel       │             │
│  │  ┌────────────────────────────────────┐                       │
│  │  │        GatewayService (HTTP)       │                       │
│  │  │  ┌──────────────────────────────┐  │                       │
│  │  │  │ GET  /health                 │  │                       │
│  │  │  │ POST /v1/chat/completions    │  │                       │
│  │  │  │      (SSE streaming)         │  │                       │
│  │  │  │ GET  /api/skills             │  │                       │
│  │  │  │ GET  /api/cron               │  │                       │
│  │  │  │ GET  /api/files              │  │                       │
│  │  │  │ GET  /api/logs               │  │                       │
│  │  │  └──────────────────────────────┘  │                       │
│  │  └────────────────────────────────────┘                       │
│  └─────────────────────────────────────────────────────┘         │
│                          │                                        │
│                          ▼                                        │
│  ┌─────────────────────────────────────────────────────┐         │
│  │                   Screen Layers                      │         │
│  │  ┌──────────┐  ┌──────┐  ┌────────┐  ┌──────────┐  │         │
│  │  │ 仪表盘   │  │ 聊天 │  │ 定时   │  │ 模型与技能│  │         │
│  │  └──────────┘  └──────┘  └────────┘  └──────────┘  │         │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  │         │
│  │  │ 文件   │  │ 平台   │  │ 日志   │  │ 设置   │  │         │
│  │  └────────┘  └────────┘  └────────┘  └────────┘  │         │
│  └─────────────────────────────────────────────────────┘         │
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

**设计原则：客户端只管界面和本地存储，GatewayService 通过 ConnectionManager 统一管理到服务端的连接。**

---

## 连接模式

Hermes Desktop 支持三种连接模式，由 `ConnectionManager` 统一管理。所有 HTTP 请求都经过同一个 `localhost:<port>` 地址，区别在于后端的连通方式。

### 本地模式 (Local)

- **适用场景**：Hermes Gateway 运行在本机 WSL 中
- **原理**：直接连接 `http://localhost:8642`，通过 `wsl.exe` 执行 shell 命令
- **配置**：填入 Gateway 地址和 API Key 即可
- **健康检查**：每 10 秒检测 `/health`，断开后自动尝试重新连接
- **重启策略**：检测 Gateway 是否运行 + API Key 是否一致，跳过不必要的重启

### 内嵌模式 (Embedded)

- **适用场景**：Windows 用户不想装 WSL，直接运行内置 hermes.exe
- **原理**：在 Windows 上直接启动绑定的 `hermes.exe` 进程，通过 cmd 执行 shell 命令
- **启动流程**：检测 `~/.hermes/` → 不存在则自动下载 → 解压 → 启动 hermes.exe
- **进程管理**：应用退出时自动 kill hermes.exe 进程，不残留后台任务
- **自动恢复**：Gateway 崩溃后健康检查自动重启

### 远程模式 (Remote/SSH)

- **适用场景**：Hermes Gateway 运行在远程 Linux 服务器（如云 VPS），本地无需 GPU
- **原理**：通过 `ssh -L` 端口转发，将远程 8642 端口映射到本地
  ```
  ssh -L <local_port>:localhost:8642 user@host
  ```
- **配置**：主机地址、SSH 端口（默认 22）、用户名、密钥路径或密码
- **自动重连**：健康检查检测到断开后自动重建 SSH 隧道
- **安全**：支持密钥认证，`StrictHostKeyChecking=accept-new`

---

## 模块详解

### 📊 仪表盘

概览页，展示系统关键指标和快捷入口：

- **统计卡片**：总会话数、已装技能数、日志大小、定时任务数
- **模型配置**：当前使用的模型、Provider、Base URL
- **机器状态**：CPU 使用率、内存占用、磁盘使用、运行时间（本地/远程模式）
- **快捷导航**：点击卡片直接跳转到对应页面
- **连接状态指示器**：在线/离线/连接中/错误，带颜色指示灯
- **一键重启 Gateway**：确认后重启，不闪烁"连接失败"状态

### 💬 聊天

核心功能，多会话并行流式聊天：

- **并行会话**：多个会话同时进行 AI 回复，互不干扰。切换会话不中断后台流
- **流式输出**：SSE（Server-Sent Events）实时显示 AI 回复，逐 token 展示
- **消息即时存盘**：用户消息发送前即写入本地数据库，API 调用失败也不丢消息
- **长回复自动分段**：AI 回复超过 2000 字自动切为多条消息气泡，防止渲染卡死
- **UI 节流**：流式更新 300ms 节流，锁屏唤醒后不触发高频重建
- **会话续聊**：Gateway session ID 持久化到本地数据库，重启应用后继续对话，上下文不丢失
- **会话管理**：创建/切换/删除/备注会话，本地搜索过滤
- **技能建议**：输入 `/` 触发技能补全列表，选中后自动插入
- **消息草稿**：切换会话自动保存输入框内容，切回恢复
- **中断回复**：AI 回复中可发送新消息中断当前回复，开始新对话
- **文件附件**：支持上传图片等文件作为多模态输入
- **复制消息**：长按或右键点击消息气泡复制内容

### ⏰ 定时任务

可视化 cron 任务管理：

- **创建任务**：编辑 cron 表达式 + 技能命令 + 参数
- **任务列表**：显示所有定时任务，支持启用/暂停/删除
- **立即执行**：手动触发任务立即运行
- **编辑任务**：修改已有任务的表达式、命令、参数
- **双源展示**：展示 Hermes 内部 cron 任务和系统 crontab 任务

### 🧠 模型与技能

模型配置和技能管理：

- **15 个 Provider**：deepseek、openrouter、anthropic、openai、gemini、kimi、ollama、glm、minimax、arcee、opencode、huggingface、qwen、xiaomi 等
- **智能填充**：切换 Provider 自动填写默认 Base URL 和推荐模型
- **技能列表**：浏览已安装的技能及其描述
- **配置生效**：保存配置后自动重启 Gateway 使新模型生效

### 📂 文件

浏览 Hermes Gateway 的文件输出：

- **目录浏览**：导航 `~/.hermes/outputs/` 目录树
- **文本预览**：直接查看文本文件内容
- **路径显示**：显示当前目录绝对路径

### 🔌 平台管理

配置 Hermes 支持的外部平台：

- **支持平台**：Telegram、Discord、Slack、WhatsApp、飞书、企业微信、Matrix、微信、钉钉、QQ Bot 等
- **配置编辑**：编辑各平台的 tokens、webhooks、接入地址
- **配置导入**：从 config.yaml 读取已有平台配置
- **保存生效**：保存后自动重启 Gateway

### 📋 日志

查看 Hermes Gateway 运行日志：

- **多源过滤**：Agent / Gateway / Error 日志切换
- **级别过滤**：INFO / WARN / ERROR / DEBUG 筛选
- **关键词搜索**：实时搜索过滤日志内容
- **一键清除**：清空指定日志文件

### ⚙️ 设置

应用全局配置和高级功能：

- **连接模式**：切换本地/内嵌/远程模式
- **Gateway 设置**：地址、API Key 配置
- **SSH 远程配置**：主机、端口、用户、认证方式
- **配置文件编辑**：内嵌编辑器修改 config.yaml、.env
- **重启 Gateway**：一键重启服务端
- **使用文档**：内置帮助文档弹窗
- **主题设置**：主题色选择 + 深色/浅色模式切换（标题栏快捷切换）

---

## 安装

### 客户端安装（桌面端）

**方式一：下载预编译 exe（推荐）**

从 [Releases 页面](https://github.com/lovesmile/hermes-desktop-ui/releases) 下载 `hermes-desktop-ui-v*.zip`，解压运行 `hermes_desktop.exe`。

**方式二：源码编译**

```bash
# 环境要求：Flutter SDK ≥ 3.0 + Visual Studio 2022 Build Tools
git clone https://github.com/lovesmile/hermes-desktop-ui.git
cd hermes-desktop-ui
flutter pub get
flutter build windows --release
```

编译产物：`build\windows\x64\runner\Release\hermes_desktop.exe`

---

### 服务端安装（Hermes Gateway）

Desktop App 是客户端，需要 Hermes Gateway 提供 AI 能力。

#### 场景 A：内嵌模式（推荐，无需额外安装）

桌面端启动后自动处理：

1. 检测 `~/.hermes/` 目录和 `hermes.exe` 是否存在
2. 如果不存在，自动从 GitHub Releases 下载 Hermes Windows 安装包
3. 解压到 `%USERPROFILE%\.hermes\` 目录
4. 自动启动 hermes.exe 并建立连接

**用户无需手动安装任何东西**，首次启动等待自动下载完成即可。

#### 场景 B：本地模式（WSL）

在 WSL 中安装 Hermes：

```bash
# 1. 安装 Hermes Agent
pip install hermes-agent

# 2. 配置 API Key
hermes setup

# 3. 启用 Gateway API Server
echo 'API_SERVER_ENABLED=true' >> ~/.hermes/.env
echo 'API_SERVER_KEY=your-secret-key' >> ~/.hermes/.env

# 4. 重启 Gateway
hermes gateway restart

# 5. 验证 Gateway 是否运行
curl http://localhost:8642/health
```

桌面端设置页选择「本地模式」，填入 Gateway 地址 `http://localhost:8642` 和 API Key。

#### 场景 C：远程模式（SSH）

**服务器端（Linux VPS）：**

```bash
pip install hermes-agent
hermes setup
echo 'API_SERVER_ENABLED=true' >> ~/.hermes/.env
echo 'API_SERVER_KEY=your-secret-key' >> ~/.hermes/.env
hermes gateway restart
```

**桌面端：** 选择「远程模式」，填写主机地址、SSH 端口、用户名、密钥，点击「测试连接」。

---

## 配置

### 配置文件

| 文件                            | 用途                                                    |
| ------------------------------- | ------------------------------------------------------- |
| `~/.hermes/desktop_config.json` | 客户端配置（Gateway 地址、API Key、连接模式、SSH 配置） |
| `~/.hermes/desktop_db.json`     | 本地数据库（所有会话和消息）                            |
| `~/.hermes/config.yaml`         | Hermes 主配置（模型、Provider 等）                      |
| `~/.hermes/.env`                | 环境变量（API Key 等）                                  |

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
      "remark": "重要项目",
      "source": "cli",
      "gateway_session_id": "gw_sess_abc123",
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

`gateway_session_id` 用于重启应用后恢复对话上下文。

---

## 构建 Release

```bash
# 打标签触发 GitHub Actions 自动构建
git tag v1.0.0
git push origin v1.0.0
```

Actions 自动：
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
| Markdown | flutter_markdown（帮助文档弹窗渲染）                   |

---

## Bridge Architecture (Connection Isolation)

Runtime uses a unified Environment Bridge architecture:

- Core interface: `HermesBridge`
- Implementations: `WslBridge`, `RemoteBridge`, `EmbeddedBridge`
- Unified entry in upper layer: `ConnectionManager.runShell(...)`

Upper-layer screens/services do not branch on connection mode for shell/file operations.
Mode-specific behavior is isolated in bridge implementations.

---

## License

MIT
