# Hermes Desktop UI — 项目总体规划

## 一句话

一个 Flutter Windows 桌面端，作为 Hermes Agent 的可视化管理面板和 AI 聊天客户端。

---

## 核心理念

### 三种连接模式（同等优先）

| 模式 | 说明 | 现状 |
|:----|:-----|:----:|
| **内嵌 Hermes** | 桌面应用自带 hermes.exe，不需要用户安装任何东西 | ✅ 已实现，稳定 |
| **本地 WSL** | 连接 WSL 中的 Hermes Gateway（`wsl.exe bash` 执行命令） | ✅ 可用 |
| **远程 SSH** | SSH 隧道连接到远程服务器的 Hermes Gateway | ✅ 基础功能可用 |

### 数据隔离

每个连接目标用独立的数据文件，互不污染：

```
desktop_db.json                  # 本地 WSL 模式
desktop_db_43_155_220_65.json    # 远程服务器 A
desktop_db_embedded.json         # 内嵌模式
```

### 三通道架构

所有业务层通过 `ConnectionManager` 统一入口路由，不按模式分支：

```
Desktop App
├── 聊天通道 → HTTP/SSE → Gateway API
├── 数据通道 → ConnectionManager.runShell()
│   ├── WslBridge (本地 WSL)
│   ├── EmbeddedBridge (内嵌 Windows)
│   └── RemoteBridge (远程 SSH)
└── 文件通道 → ConfigService / HermesFileService
    ├── 本地: dart:io 直接读写
    ├── 内嵌: dart:io 直接读写
    └── 远程: base64 + SSH echo
```

---

## 当前架构

### 核心文件

| 文件 | 职责 |
|:----|:-----|
| `main.dart` | 入口，NavigationRail 导航 |
| `connection_manager.dart` | 连接管理：SSH 隧道、三种模式桥接、状态通知、健康检查、嵌入式进程管理 |
| `gateway_service.dart` | Gateway API 客户端（聊天 SSE、状态查询） |
| `config_service.dart` | 配置读写（config.yaml / .env / desktop_config），适配三种模式 |
| `local_db.dart` | 本地数据库（会话+消息持久化，按模式隔离） |
| `hermes_file_service.dart` | 统一文件操作（通过 runShell 自动路由） |

### 页面

| 页面 | 文件 | 说明 |
|:----|:-----|:-----|
| 仪表盘 | `dashboard_screen.dart` | 统计卡片 + 快捷导航 |
| 聊天 | `chat_screen.dart` | 主聊天界面，流式 SSE |
| 定时任务 | `cron_screen.dart` | cron 任务管理 |
| 模型与技能 | `models_screen.dart` | 模型配置 + 技能列表 |
| 文件管理 | `files_screen.dart` | 远程/本地文件浏览 |
| 平台管理 | `platforms_screen.dart` | 多平台渠道配置 |
| 日志 | `logs_screen.dart` | 日志查看与过滤 |
| 设置 | `settings_screen.dart` | 连接模式切换、SSH 配置 |

### 导航栏顺序

```
仪表盘 → 聊天 → 定时 → 模型与技能 → 文件 → 平台 → 日志 → 设置
```

---

## 已完成

### 内嵌模式 (已完成)

- hermes.exe 进程管理（启动/停止/健康检查/自动重启）
- 锁冲突处理（taskkill + lock 文件清理）
- 动态端口分配（避免与 WSL gateway 冲突）
- 自动下载安装（首次启动）

### 连接管理优化

- 本地模式跳过不必要的 Gateway 重启（密钥一致时）
- 三种模式切换时自动隔离数据（DB/配置命名空间）
- 健康检查定时器（10s 间隔）
- Gateway 崩溃自动重启

### 模型配置

- 15 个 Provider 支持
- YAML 配置写入（非正则方式）
- 保存后自动重启 Gateway
- 内嵌模式重启后重写配置（避免 hermes.exe 覆盖）

### 会话管理

- [x] DisplaySession 架构（展示层/后端层解耦，切换模型不丢 title/remark）
- [x] 展示层隔离（stable display_id + backendIdHistory）
- [x] 旧版数据自动迁移（v1.0.3→v1.0.4 首次启动自动转 DisplaySession）
- [x] 备注功能（覆盖显示标题）
- [x] 按来源分组过滤
- [x] 消息实时存盘

---

## 待实现

### P1 — Chat UX 完善

- [x] 思考指示器（脉冲点动画）
- [x] 停止按钮（红色中断）
- [x] 自动中断（发新消息→取消旧流）
- [ ] 消息可编辑/撤回
- [ ] 消息搜索（Ctrl+F）
- [ ] 会话分组折叠

### P2 — 远程模式完善

- SSH 隧道断线自动重连
- 仪表盘远程指标完整支持

### P3 — 通用功能

- 系统托盘 + 后台运行
- 快捷键支持
- 主题自定义

### SKill Store

- 注册表加载（多 CDN 镜像）
- 技能安装/卸载/更新

---

## 已知 Bug

1. 远程模式切换后数据刷新不完全（仪表盘有时还是旧数据）
2. SSH 复杂命令可能因引号转义问题失败

---

## 编译与部署

```powershell
# 构建
f:\flutter\bin\flutter.bat build windows --release

# 输出路径
build\windows\x64\runner\Release\hermes_desktop.exe

# GitHub Release
git tag v1.0.4 && git push origin v1.0.4
# Actions 自动构建 + 安装包 + 上传 Release
```

---

## 项目地址

https://github.com/lovesmile/hermes-desktop-ui
