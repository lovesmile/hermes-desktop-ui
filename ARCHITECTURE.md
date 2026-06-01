# Hermes Desktop — Flutter 桌面管理面板

## 架构概述

桌面 Flutter 应用，通过 Hermes Gateway 的 REST API 和直接读取配置文件管理 Hermes Agent。

```
Flutter Desktop App (Windows)
    │
    ├── HTTP/REST ──→ Hermes Gateway (本地/远程/:port)
    │                    ├── 聊天 SSE 流
    │                    ├── 会话管理
    │                    ├── 定时任务 CRUD
    │                    ├── 平台配置
    │                    ├── 技能查询
    │                    └── 文件浏览
    │
    ├── File I/O ──→ ~/.hermes/config.yaml
    │               └── ~/.hermes/.env
    │
    └── File I/O ──→ ~/.hermes/logs/
                    └── ~/.hermes/sessions/
```

## 连接模式

Hermes Desktop 支持三种模式，由 `ConnectionManager` 统一管理：

| 模式      | Shell 桥       | 文件操作         | 场景                    |
| --------- | -------------- | ---------------- | ----------------------- |
| **Local**  | `WslBridge`    | WSL bash 命令    | 本地 WSL Hermes         |
| **Embedded** | `EmbeddedBridge` | Windows dart:io | 内嵌 hermes.exe         |
| **Remote**  | `RemoteBridge` | SSH 远程命令     | 远程服务器 Hermes       |

所有业务层代码通过 `ConnectionManager.runShell()` 统一入口，不按模式分支。

## 功能模块

### 1. 仪表盘 (Dashboard)
- Hermes 运行状态概览
- 统计卡片（会话数/技能数/日志大小/定时任务数）
- 快捷导航至各页面

### 2. AI 聊天 (Chat)
- SSE 实时流式对话
- 多会话并行（切换不中断后台流）
- 会话管理（创建/删除/重命名/备注）
- 消息实时存盘
- Markdown / 代码高亮展示

### 3. 定时任务 (Cron)
- 可视化列表（名称/定时/状态/上次运行）
- 创建/编辑/暂停/恢复/删除
- 立即执行
- 常用 Cron 表达式快捷选择

### 4. 模型与技能 (Models & Skills)
- 15 个 Provider 选择（deepseek→xiaomi）
- 模型配置保存后自动重启 Gateway
- 技能列表 + 右键快捷关联聊天

### 5. 文件浏览 (Files)
- 通过 Gateway API 浏览 `~/.hermes/outputs/`
- 目录导航
- 文本文件预览 + 复制

### 6. 平台管理 (Platforms)
- 10+ 平台集中配置
- 表单式编辑，保存后触发网关重启
- 状态指示（已配置/未配置/异常）

### 7. 日志查看 (Logs)
- Agent / Gateway / Error 三栏
- 按级别/关键词过滤
- 清空/删除日志文件

### 8. 设置 (Settings)
- 连接模式选择器（本地/内嵌/远程）
- SSH 配置表单（主机/端口/用户/密钥路径）
- SSH 连接测试
- Gateway 地址/端口/API Key 配置
- config.yaml / .env 编辑器
- 重启 Gateway
- 使用文档（内置 Markdown）

## 核心文件

| 文件 | 职责 |
|:----|:-----|
| `main.dart` | 入口，NavigationRail 导航，会话列表 |
| `connection_manager.dart` | 连接管理：SSH 隧道、三种模式桥接、状态通知、健康检查 |
| `gateway_service.dart` | Gateway API 客户端（聊天 SSE、状态查询） |
| `config_service.dart` | 配置读写（config.yaml / .env / desktop_config），适配三种模式 |
| `local_db.dart` | 本地数据库（会话+消息持久化，按模式/服务器隔离） |
| `hermes_file_service.dart` | 统一文件操作（通过 runShell 自动路由） |

## 技术栈

- **Flutter 3.x** — Windows Desktop
- **Dart** — 主要开发语言
- **HTTP/SSE** — Gateway API 通信
- **dart:io** — 文件 I/O + 进程管理
- **Material Design 3** — UI 主题

## Environment Bridge Layer

为避免业务层 `if (mode == ...)` 分支和硬编码路径冲突，运行时采用桥接隔离：

### Layers

1. **业务/UI 层**
   - 只调 `ConnectionManager`
   - 无模式相关分支

2. **环境抽象层**
   - `HermesBridge` 接口定义 shell 执行契约
   - `ConnectionManager` 按模式路由

3. **模式实现层**
   - `WslBridge`: `wsl.exe -d <distro> bash -c`
   - `RemoteBridge`: SSH 远程命令执行
   - `EmbeddedBridge`: Windows `cmd /c` 或 `Process.start`

### 切换契约

切换模式时，`ConnectionManager` 统一执行：
- 更新本地 DB 命名空间（模式/服务器隔离）
- 更新配置命名空间
- 刷新 Gateway base URL
- 更新当前 server ID
