## 相关技能（Hermes Skills）

项目相关的 skill 文件，加载后包含详细的技术规范：

### `hermes-desktop-ui`
位置：`~/.hermes/skills/software-development/hermes-desktop-app/SKILL.md`

| 章节 | 内容 |
|:----|:-----|
| M3 主题 | ColorScheme.fromSeed、静态颜色禁令、深浅色规范 |
| Session 格式 | 文件解析、去重、过滤、分页缓存 |
| 连接模式 | 三模式桥接（Local/Embedded/Remote） |
| 聊天 UX | 思考指示器、停止按钮、自动中断 |
| 数据隔离 | IP namespace、DB 文件隔离、runShell 路由 |

### `test-driven-development`
TDD 规范：RED → GREEN → REFACTOR，测试优先。

### `systematic-debugging`
当遇到 bug 时，用科学方法诊断：假设 → 验证 → 根因 → 修复。

---

## 当前会话记忆摘要

关于这个项目，Hermes 的持久记忆中有以下关键信息：

- Flutter Windows Desktop，M3 主题，ColorScheme.fromSeed
- 三种连接模式：Local（WSL）、Embedded（Windows 原生）、Remote（SSH）
- 连接管理由 ConnectionManager 单例统一路由
- 数据按模式/服务器隔离（desktop_db_{mode}.json）
- 内嵌模式：hermes.exe 进程管理，taskkill 清理，健康检查自动重启
- 模型配置保存后自动重启 Gateway
- 仪表盘卡片可点击导航至对应页面

---

## 首尔服务器信息

远程测试服务器：`ubuntu@43.155.220.65:22`
密码认证（keyPath 和 password 都空时，Windows 默认 SSH 密钥）
Hermes 路径：`~/.hermes/`
Gateway API：`localhost:8642`（通过 SSH 隧道转发）
