# Hermes Desktop — Flutter 桌面管理面板

## 架构概述

桌面 Flutter 应用，通过 Hermes Gateway 的 REST API (端口 8642) 和直接读取配置文件管理 Hermes Agent。

```
Flutter Desktop App (Windows)
    │
    ├── HTTP/REST ──→ Hermes Gateway (WSL, :8642)
    │                    ├── 聊天 SSE 流
    │                    ├── 会话管理
    │                    ├── 定时任务 CRUD
    │                    └── 平台配置
    │
    ├── File I/O ──→ ~/.hermes/config.yaml
    │               └── ~/.hermes/.env
    │
    └── File I/O ──→ ~/.hermes/logs/
                    └── ~/.hermes/sessions/
```

## 功能模块

### 1. 仪表盘 (Dashboard)
- Hermes 运行状态概览（网关在线/离线）
- Token 用量统计（总数/输入/输出，近30天趋势）
- 会话数统计
- 模型使用分布

### 2. AI 聊天 (Chat)
- SSE 实时流式对话
- 多会话管理（创建/重命名/删除/切换）
- 按来源分组（Telegram/Discord/CLI 等）
- 工具调用参数和结果展开查看
- Markdown / 代码高亮展示
- Ctrl+K 全局搜索对话

### 3. 平台管理 (Platforms)
- 8个平台集中配置（Telegram/Discord/Slack/WhatsApp/飞书/企微/Matrix/微信）
- 表单式编辑，修改后触发网关重启
- 状态指示（已配置/未配置/异常）

### 4. 定时任务 (Cron)
- 可视化列表（名称/定时/状态/上次运行）
- 创建/编辑/暂停/恢复/删除
- 立即执行按钮
- 常用 Cron 表达式快捷选择

### 5. 日志查看 (Logs)
- Agent 日志 / 网关日志 / 错误日志 三栏
- 按级别/关键词过滤
- 结构化日志解析
- HTTP 访问日志高亮

### 6. 模型管理 (Models)
- 凭证池自动发现 (~/.hermes/auth.json)
- Provider 列表（新增/编辑/删除）
- 测试连接

### 7. 设置 (Settings)
- YAML 配置文件可视化编辑
- Profile 切换
- 主题切换（亮色/暗色）

## 技术栈

- **Flutter 3.x** — Desktop (Windows/WSL)
- **Dart** 语言
- **HTTP/REST** — `http` 包调用 Gateway API
- **SSE** — 自定义 SSE 客户端处理流式响应
- **File I/O** — `dart:io` 读取配置文件
- **状态管理** — `provider` 或 `riverpod`
- **UI** — Material Design 3 (Material You)

## 路由结构

```
/                    → 仪表盘
/chat                → 聊天列表
/chat/:id            → 具体会话
/platforms           → 平台管理
/cron                → 定时任务
/logs                → 日志查看
/settings            → 设置
/models              → 模型管理
```

## Gateway API 端点（需验证）

| 端点 | 方法 | 用途 |
|------|------|------|
| /api/chat | POST/SSE | 发送消息/流式回复 |
| /api/sessions | GET | 会话列表 |
| /api/sessions/:id | GET/DELETE | 会话详情/删除 |
| /api/config | GET/PUT | 配置读写 |
| /api/cron | GET/POST | 定时任务列表/创建 |
| /api/cron/:id | PUT/DELETE | 更新/删除 |
| /api/logs | GET | 日志查询 |
| /api/health | GET | 健康检查 |
| /api/gateway/restart | POST | 重启网关 |
