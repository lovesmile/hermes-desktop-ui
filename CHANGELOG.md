# Changelog

## [1.0.8+1] — 2026-06-17

### 多会话隔离修复
- 每个会话独立的发送状态 `_sendingPerSession[sessionId]`，切换会话不再打断另一个会话的回复
- 移除 `_pendingMessages` 暂存机制，消息在流结束时直接持久化到 DB，关闭程序不丢消息
- 修复新会话创建时 subscription/buffer key 混乱问题（`localDisplayId` vs `__pending__` 导致 sending 状态无法清除）
- 修复 `createSession` 的 `UNIQUE constraint` 冲突（改用 `ConflictAlgorithm.replace`）
- 修复 `sendMessage` 中 `cancelCurrentChat` 错误取消新会话订阅的问题

### 启动加载修复
- `main()` 中 `runApp()` 前先从配置读取连接模式并 `setMode()`，避免 UI 先加载默认 local DB 数据
- `DashboardScreen.initState()`：只有 `status == connected` 时才立即加载，否则等连接建立后再加载
- 远程连接关闭后重启，仪表盘/技能/文件/定时任务数据正确刷新

### 刷新机制闭环
- `ConnectionManager._onStateChanged()`：状态变成 `connected` 时统一触发 `refreshNotifier`
- `DashboardScreen._onConnectionChanged()`：直接监听 `stateNotifier`，仅 `connected` 时加载，不走 `refreshNotifier` 绕路
- 各屏监听自己需要的信号，职责分开，避免频繁刷新

---

## [1.0.7+1] — 2026-06-17

### 主题系统升级
- 应用 Hermes Modern 固定配色系统（深色/浅色模式使用固定色值，非 M3 `ColorScheme.fromSeed` 动态生成）
- 正文默认字体改为 **Inter**，等宽字体改为 **JetBrains Mono**

### 预览修复
- 修复会话列表预览不更新：消息到达时未持久化 preview 字段
- 修复切换后端时 preview 不更新问题

---

## [1.0.6] — 2026-06-16

### 技能商店合并
- 技能商店合并到模型页面 Tab
- 移除按会话切换模型功能
