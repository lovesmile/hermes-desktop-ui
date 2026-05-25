# Hermes Desktop UI — 项目总体规划

## 一句话

一个 Flutter Windows 桌面端，作为 Hermes Agent 的可视化管理面板和 AI 聊天客户端。

---

## 核心理念

### 三种连接模式（按优先级排列）

| 模式 | 说明 | 现状 |
|:----|:-----|:----:|
| **远程 SSH** | SSH 隧道连接到远程服务器的 Hermes Gateway | ✅ 基础功能可用，有 bug |
| **本地 WSL** | 连接用户已有的 WSL + Hermes（`wsl.exe bash` 执行命令） | ✅ 可用 |
| **内嵌 Hermes** | 桌面应用自带 Hermes，不需用户安装任何东西 | ❌ 未实现，最高优先级 |

**原则：** 用户没装 Hermes → 自动用内嵌的。用户装了自己的 Hermes → 优先连接已有的（本地或远程）。

### 数据隔离

每个连接目标用独立的数据文件，互不污染：

```
desktop_db.json                  # 本地 WSL 模式
desktop_db_43_155_220_65.json    # 远程服务器 A
desktop_db_new_ip.json           # 远程服务器 B
```

### 双通道架构

```
Desktop App
├── 聊天通道 → HTTP/SSE → Gateway API (SSH 隧道 for 远程)
└── 数据通道 → 文件 I/O
    ├── 本地模式: WSL bash + dart:io
    ├── 远程模式: SSH exec 命令
    └── 未来(内嵌): Windows 原生命令
```

---

## 当前架构

### 核心文件

| 文件 | 职责 |
|:----|:-----|
| `main.dart` | 入口，初始化 ConnectionManager |
| `connection_manager.dart` | 连接管理：SSH 隧道、execRemote、runShell、状态通知 |
| `hermes_file_service.dart` | 统一文件操作（通过 runShell 自动路由本地/远程） |
| `ssh_file_service.dart` | SSH 文件读取（readFile、listFiles、readTail） |
| `gateway_service.dart` | Gateway API 客户端（聊天 SSE、session 文件操作） |
| `local_db.dart` | 本地数据库（会话+消息持久化，按模式隔离） |
| `config_service.dart` | 配置/技能/日志读取（远程时走 SSH） |

### 页面

| 页面 | 文件 | 说明 |
|:----|:-----|:-----|
| 仪表盘 | `dashboard_screen.dart` | 统计卡片（会话/技能/日志/cron） |
| 聊天 | `chat_screen.dart` | 主聊天界面，流式 SSE |
| 设置 | `settings_screen.dart` | 连接模式切换、SSH 配置 |
| 文件管理 | `files_screen.dart` | 远程/本地文件浏览 |
| 设置向导 | `setup_screen.dart` | 首次启动的设置向导（远程/本地安装） |
| 定时任务 | `cron_screen.dart` | cron 任务管理 |
| 平台管理 | `platforms_screen.dart` | 多平台渠道配置 |

### 聊天实现

- SSE 流式回复，StreamSubscription 管理
- `_sending` + `_streamingContent` 控制状态
- `_interrupted` 标记被动中断
- `_isThinking` getter：`_sending && _streamingContent.isEmpty`
- 取消/中断：`_cancelCurrentChat()` 取消所有订阅
- 切会话时旧流在后台跑完（不中断），切换回来时回复已缓存

---

## 待实现（按优先级）

### P0 — 内嵌 Hermes（最高优先级）

**目标：** 用户下载 Desktop exe 后直接运行，不需要 WSL，不需要手动安装 Hermes。

**方案：** 
1. 在 GitHub Release 中附带一个 `hermes-bundle-windows.zip`（包含 Python + Hermes + 依赖）
2. Desktop 首次启动时检测 → 如果没有 → 弹出安装向导 → 下载 → 解压 → 启动
3. `ConnectionManager` 增加 Windows 原生模式：直接运行 Hermes 进程（`Process.start`），不走 WSL bash
4. `HermesFileService` 增加 Windows 原生的文件操作（不依赖 bash）

**当前状态：** 安装向导框架已有（`setup_screen.dart`），下载路径和 bundle 结构需要定义。

### P1 — 远程模式完善

- `execRemote` SSH 命令可靠性（引号转义、密码回显、超时处理）
- 仪表盘数据在远程模式下的完整刷新
- 文件浏览器：支持 `.hermes/` 目录快捷导航
- SSH 隧道断线自动重连
- 清除缓存按钮（手动触发 `_loadData`）

### P2 — Chat UX 完善

- [x] 思考指示器（脉冲点动画）
- [x] 停止按钮（红色中断）
- [x] 自动中断（发新消息→取消旧流）
- [ ] 消息可编辑/撤回
- [ ] 消息搜索（Ctrl+F）
- [ ] 会话分组折叠

### P3 — 通用功能

- 本地化缓存：远程读取的技能/配置/cron 数据缓存到本地
- 设置页支持多台远程服务器配置保存（不是覆盖，是列表）
- 快捷键支持
- 系统托盘 + 后台运行

---

## 已知 Bug

1. 远程模式切换后数据刷新不完全（仪表盘有时还是旧数据）
2. SSH `execRemote` 复杂命令可能因引号转义问题失败
3. 文件浏览器默认路径是 `$HOME`，应改为 `~/.hermes/`
4. 远程连接成功后设置页状态栏不及时更新

---

## 编译与部署

```powershell
# 构建
f:\flutter\bin\flutter.bat build windows --release

# 输出路径
build\windows\x64\runner\Release\hermes_desktop.exe

# GitHub Release
git tag v1.x.x && git push origin v1.x.x
# Actions 自动构建 + zip 打包 + 上传 Release
```

---

## 项目地址

https://github.com/lovesmile/hermes-desktop-ui
