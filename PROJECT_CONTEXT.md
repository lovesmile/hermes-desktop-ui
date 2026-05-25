## 相关技能（Hermes Skills）

项目相关的 skill 文件，加载后包含详细的技术规范：

### `hermes-desktop-ui`
位置：`~/.hermes/skills/software-development/hermes-desktop-app/SKILL.md`

| 章节 | 内容 |
|:----|:-----|
| M3 主题 | ColorScheme.fromSeed、静态颜色禁令、深浅色规范 |
| Session 格式 | 文件解析、去重、过滤、分页缓存 |
| Gateway Auth 架构 | API_SERVER_KEY 双层设计、sessionId 续传 |
| 聊天 UX | 思考指示器、停止按钮、自动中断 |
| SSH + 数据隔离 | IP namespace、DB 文件隔离、execRemote、runShell |

### `test-driven-development`
位置：`~/.hermes/skills/software-development/test-driven-development/SKILL.md`

TDD 规范：RED → GREEN → REFACTOR，测试优先。

### `systematic-debugging`
位置：`~/.hermes/skills/software-development/systematic-debugging/SKILL.md`

当遇到 bug 时，用科学方法诊断：假设 → 验证 → 根因 → 修复。

---

## 当前会话记忆摘要

关于这个项目，Hermes 的持久记忆中有以下关键信息：

- Flutter Windows Desktop，M3 主题，ColorScheme.fromSeed
- `connectRemote` 成功时调用 `LocalDatabase().setMode(host)` + `ConfigService().setMode(host)`
- `switchToLocal` 同理设回 `'local'`
- `chatStream` 的 `onCancel` 不能关全局 HttpClient
- 切会话时旧流在后台跑完（不中断）
- `_sending = true` 对所有会话设置（bug：之前只对新会话设）

---

## 首尔服务器信息

远程测试服务器：`ubuntu@43.155.220.65:22`
密码认证（keyPath 和 password 都空时，Windows 默认 SSH 密钥）
Hermes 路径：`~/.hermes/`（远程）
Gateway API：`localhost:8642`（通过 SSH 隧道转发）
