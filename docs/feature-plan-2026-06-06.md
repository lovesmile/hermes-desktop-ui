# Hermes Desktop — 功能扩展计划

> 基于官方 Hermes Desktop (Electron) v0.16.0 的功能分析
> 按优先级（简单→中等→工作量大）排列，每步不破坏现有功能

---

## 架构原则

### 现有架构（严格遵守）

```
Flutter App
  ├── main.dart          ← 入口 + NavigationRail
  ├── screens/           ← 页面（chat_screen, cron_screen, 等）
  │   └── chat_screen.dart  ← 聊天页面（~1600行，单一 StatefulWidget）
  ├── services/          ← 服务层（GatewayService, LocalDatabase, ConfigService, SseService）
  │   └── gateway_service.dart  ← Gateway API 客户端（单例）
  └── widgets/           ← 可复用组件
      └── chat_message.dart    ← 消息气泡组件
```

### 编码约束

1. **不修改三层架构** — 业务层只调 `ConnectionManager` / `GatewayService`，不直接调模式实现
2. **单例模式** — GatewayService 等用 `factory` 单例，不创建新实例
3. **state 管理** — 当前用 `setState` 不引入新框架（Provider 只用在外层）
4. **不拆分 _ChatScreenState** — 当前 ~1600 行，加功能时逐步增量，不重构现结构
5. **不改现有消息/会话模型** — `_Message`、`Session`、`_attachedFiles` 结构不变
6. **新增代码放新文件** — 新增功能不塞进现有大文件，建独立文件

---

## 第一阶段：简单功能（⭐）

### 1.1 拖拽文件到聊天区

**目标**：将文件拖到输入区上方，自动添加为附件（与 `_pickFile()` 效果一致）

**实现方案**：

**文件**：`lib/widgets/chat_drop_zone.dart`（新增）

```dart
/// 包裹输入区的拖拽区域
/// 拖入时显示半透明遮罩提示，松开后调用 _onFileDropped 回调
class ChatDropZone extends StatelessWidget {
  final Widget child;
  final ValueChanged<List<DroppedFile>> onFileDropped;

  // 使用 DragTarget<List<File>> 或自建 Listener 检测拖入
  // 维护 _isDragOver 状态控制遮罩显隐
}
```

**修改现有文件**：`chat_screen.dart`
- 在输入区（`Container` at ~L970）外套一层 `ChatDropZone`
- `onFileDropped` 回调 → 读取文件 → base64 → 加到 `_attachedFiles`
- 复用 `_makeAttachment()` 方法

**验证方法**：
1. 拖入图片 → 附件 chip 出现 ✅
2. 拖入 PDF → 附件 chip 出现 ✅
3. 拖到非输入区 → 无反应 ✅
4. `_pickFile()` 按钮仍然可用 ✅

**风险**：无。纯 UI 层，不涉及后端

---

### 1.2 剪贴板图片粘贴

**目标**：Ctrl+V / Cmd+V 粘贴剪贴板中的图片到附件

**实现方案**：

**修改文件**：`chat_screen.dart`

在 `build()` 的输入 `TextField` 外层包 `Shortcuts` + `Actions`：

```dart
Shortcuts(
  shortcuts: {
    // 检测 Ctrl+V / Cmd+V
    SingleActivator(LogicalKeyboardKey.keyV, control: true, meta: true): _PasteImageIntent(),
  },
  child: Actions(
    actions: {
      _PasteImageIntent: _PasteImageAction(
        onPaste: () async {
          final imageData = await Clipboard.getImage();
          if (imageData != null) {
            // 转 base64 → 生成 Attachment → 加到 _attachedFiles
            setState(() { _attachedFiles.add(...); });
          }
        },
      ),
    },
    child: originalInputWidget,
  ),
)
```

**验证方法**：
1. 截图 → Ctrl+V → 附件 chip 出现 ✅
2. 复制图片 → Ctrl+V → 附件 chip 出现 ✅
3. 复制文字 → Ctrl+V → 正常粘贴文字，不误触发 ✅
4. `_pickFile()` 仍然可用 ✅

**风险**：低。需注意 `Clipboard.getImage()` 在 Windows 上兼容性，若返回 null 则静默忽略

---

### 1.3 状态栏一键切换模型

**目标**：在底部加一个模型选择下拉菜单，选中后调后端 `/api/model/set` 接口

**实现方案**：

**文件**：`lib/widgets/model_switcher.dart`（新增）
```dart
/// 模型选择下拉按钮
/// 显示当前模型名 → 点击展开菜单 → 列表从后端 API 获取 → 选中后调 set
class ModelSwitcher extends StatefulWidget {
  // 内部通过 GatewayService 调 model.options / model.set
}
```

**新增 GatewayService 方法**：

```dart
// gateway_service.dart 新增
Future<List<Map<String, dynamic>>> getModelOptions() async { ... }
Future<bool> setModel(String provider, String model) async { ... }
```

**修改文件**：`chat_screen.dart`
- 在 AppBar 或输入区上方加一个 `PopupMenuButton` 显示当前模型
- 调用 `_gateway.getModelOptions()` 获取可用模型列表
- 选中后调 `_gateway.setModel()`

**验证方法**：
1. 下拉展开显示当前模型 ✅
2. 可选模型列表正确 ✅
3. 切换后状态栏更新 ✅
4. 聊天请求使用新模型 ✅

**风险**：低。调现有后端接口，不涉及流式逻辑修改

---

## 第二阶段：中等功能（⭐⭐）

### 2.1 会话搜索（本地 FTS5）

**目标**：在会话侧边栏搜索框输入时，按标题/预览/备注搜索本地 SQLite 数据

**实现方案**：

**当前已有**：`_buildSessionList()` 中已有搜索框和 `q.contains()` 过滤（~L1080）

**升级方案**：

**修改文件**：`local_db.dart` 新增 FTS5 搜索：

```dart
// local_db.dart 新增
Future<List<Session>> searchSessions(String query) async {
  // 搜索 sessions 表中 title / remark / preview 列
  // 用 SQLite LIKE 替代当前的内存 contains（更大数据集时更高效）
  final db = await database;
  final results = await db.rawQuery('''
    SELECT * FROM sessions
    WHERE title LIKE ? OR remark LIKE ? OR preview LIKE ?
    ORDER BY updated_at DESC
    LIMIT 50
  ''', ['%$query%', '%$query%', '%$query%']);
  return results.map((r) => Session.fromMap(r)).toList();
}
```

**修改文件**：`chat_screen.dart`
- 搜索有输入时调 `_localDb.searchSessions()` 替代当前 `_sessions.where(...).contains(q)`
- 加 debounce（300ms）避免每次按键都查

```dart
Timer? _searchDebounce;
void _onSearchChanged(String q) {
  _searchDebounce?.cancel();
  _searchDebounce = Timer(Duration(milliseconds: 300), () async {
    if (q.isEmpty) {
      setState(() => _displayedSessions = _sessions.take(_sessionPageSize).toList());
    } else {
      final results = await _localDb.searchSessions(q);
      setState(() => _displayedSessions = results);
    }
  });
}
```

**验证方法**：
1. 输入关键词 → 过滤到匹配会话 ✅
2. 清空搜索 → 恢复正常列表 ✅
3. 搜索性能：300ms debounce 不卡 UI ✅
4. 搜索+置顶同时生效 ✅

**风险**：低。搜本地 DB，不涉及网络

---

### 2.2 语音输入（STT）

**目标**：按住麦克风按钮录音 → 自动转文字 → 填入输入框

**实现方案**：

**新增依赖**：`pubspec.yaml` 加 `record: ^5.0.0` 或 `flutter_sound: ^9.0.0`

**文件**：`lib/services/voice_service.dart`（新增）
```dart
class VoiceService {
  // 录音 → 保存为临时 WAV → POST /api/audio/transcribe → 返回文本
  Future<String?> transcribe() async { ... }
}
```

**文件**：`lib/widgets/voice_input_button.dart`（新增）
```dart
/// 按住录音按钮
/// 开始录音 → 录音中显示波纹动画 → 松开停止 → 调 VoiceService → 填入输入框
```
 
▶ 按钮 → ▶|■ 录音动画 → ■| 填文字

**GatewayService 新增**：

```dart
// gateway_service.dart 新增
Future<String?> transcribeAudio(String audioBase64) async {
  // POST /api/audio/transcribe { audio: base64 }
  // 返回 text
}
```

**修改文件**：`chat_screen.dart`
- 在输入区发送按钮旁加一个麦克风图标按钮
- 调用 `VoiceService.transcribe()` → 结果填入 `_inputController.text`

**验证方法**：
1. 按住录音 → 出现录音动画 ✅
2. 松开 → 文字填入输入框 ✅
3. 录音失败 → 无文字，不崩溃 ✅

**风险**：中。需要处理麦克风权限、录音文件临时存储、音频格式兼容性

### 2.3 语音输出（TTS）

**目标**：AI 回复完成后，点击朗读按钮播放语音

**实现方案**：

**新增依赖**：`pubspec.yaml` 加 `audioplayers: ^6.0.0`

**文件**：`lib/services/voice_service.dart` 扩展现有

```dart
// VoiceService 新增
class VoiceService {
  Future<String?> transcribe(String audioB64) async { ... }
  
  // TTS: 文字 → POST /api/audio/speak → 返回音频 → 播放
  Future<void> speak(String text) async {
    final audioB64 = await _gateway.speakText(text);
    // 解码 base64 → 临时文件 → audioplayers 播放
  }
  
  void stopSpeaking() { /* 停止当前播放 */ }
}
```

**修改文件**：`chat_message.dart`
- 在 AI 消息气泡右下角加一个小喇叭图标按钮
- 点击 → 调 `VoiceService.speak(message.text)`

**验证方法**：
1. 点击朗读按钮 → 播放语音 ✅
2. 长消息只朗读前 2000 字 ✅
3. 点击另一个朗读 → 先停旧的再播新的 ✅

**风险**：中。TTS 播放需异步缓存音频，注意临时文件清理

---

## 第三阶段：工作量大（⭐⭐⭐）

### 3.1 流式工具调用展示

**目标**：在聊天消息中显示 AI 调用的工具（搜索/读文件等），实时展示进度

**当前限制**：SSE 流只返回 OpenAI 格式的 `choices[0].delta.content`，不包含工具调用事件

**实现方案**：

**步骤一：GatewayService 升级（从 SSE → 变 WebSocket）**

SSE 目前只拿文本 delta。工具调用需要 WebSocket 事件（`tool.start` / `tool.progress` / `tool.complete`）。

```dart
// gateway_service.dart 新增
class GatewayWsClient {
  WebSocketChannel? _channel;
  
  Stream<GatewayEvent> connect(String url) {
    // ws://host/ws 连接
    // 接收 JSON-RPC 事件 → 解析为 GatewayEvent 联合类型
  }
}

// 事件模型
sealed class GatewayEvent {}
class ToolStartEvent extends GatewayEvent { String toolId; String toolName; Map args; }
class ToolProgressEvent extends GatewayEvent { String toolId; String status; }
class ToolCompleteEvent extends GatewayEvent { String toolId; String result; }
class TextDeltaEvent extends GatewayEvent { String text; }
```

**步骤二：消息模型升级**

`_Message` 现有 `toolCalls` 字段，需要扩展为完整工具调用渲染：

```dart
class _Message {
  // 现有
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  
  // 新增
  final List<ToolCallInfo>? toolCalls;  // 已有但未渲染
}
```

**步骤三：工具调用 UI**

在 `chat_message.dart` 中渲染工具卡片（折叠态）：

```
┌──────────────────────┐
│ 🔍 搜索 "xxx"        │  ← 工具名 + 参数
│ ⏳ 搜索中...         │  ← 进度状态
└──────────────────────┘
```
完成后自动收起，只留一个展开箭头。

**风险**：**高**。需要：
- 后端升级 SSE → WebSocket（需确认 API Server 是否支持 WS 协议）
- 重建流式连接管理器
- 不破坏现有 SSE 链路（可双通道并行：SSE 走文本，WS 走工具事件）
- 消息模型改为不可变 + 增量更新

**建议**：等确认 API Server 支持 WebSocket 后再做。先确认 Hermes Gateway 的 WS 端点路径和事件格式。

---

### 3.2 Cmd+K 命令面板

**目标**：按 Ctrl+K / Cmd+K 弹出一个搜索式命令菜单（类似 VS Code）

**实现方案**：

**文件**：`lib/widgets/command_palette.dart`（新增）

```dart
class CommandPalette extends StatefulWidget {
  // 全屏遮罩 + 搜索框 + 结果列表
  // 搜索动作包括：打开页面、切换模型、搜索会话、加载技能
}
```

**主要组件**：
- `OverlayEntry` / `showDialog` 全屏模态
- `TextField` 自动聚焦
- 分组命令列表：`Go to`, `Actions`, `Settings`
- 按输入过滤，支持模糊匹配
- 选中后执行动作并关闭面板

**调用方式**：在 `chat_screen.dart` 或 `main.dart` 监听键盘快捷键

```dart
// main.dart
CallbackShortcuts(
  bindings: {
    SingleActivator(LogicalKeyboardKey.keyK, control: true, meta: true):
      () => showCommandPalette(context),
  },
  child: MaterialApp(...),
)
```

**命令列表**（按类别分组）：

| 组 | 命令 | 操作 |
|----|------|------|
| 导航 | 新对话 | `_newChat()` |
| 导航 | 仪表盘 | 切换到 dashboard_screen |
| 导航 | 定时任务 | 切换到 cron_screen |
| 导航 | 设置 | 切换到 settings_screen |
| 动作 | 切换模型 | 弹出模型选择器 |
| 动作 | 搜索会话 | 聚焦侧边栏搜索框 |
| 动作 | 加载技能 | 输入 /skill_name 并发送 |
| 设置 | 切换主题 | light/dark 切换 |
| 设置 | 重启 Gateway | 调 `_gateway.restartGateway()` |

**验证方法**：
1. Ctrl+K → 面板弹出 ✅
2. 输入过滤 → 结果实时更新 ✅
3. 选中命令 → 面板关闭 + 执行动作 ✅
4. Escape → 面板关闭 ✅

**风险**：中。纯前端，不涉及后端和 SSE。主要工作量在命令列表维护和 UI 细节

---

### 3.3 侧边预览（Side-by-Side Previews）

**目标**：在聊天区右侧加一个预览面板，显示 AI 返回的网页/文件内容

**实现方案**：

**文件**：`lib/widgets/preview_panel.dart`（新增）

```dart
class PreviewPanel extends StatelessWidget {
  // 右侧面板：TabBar 切换预览目标
  // 支持：URL 预览、文件预览、日志预览
  // 从消息中提取 [Preview:name](#preview/url) 标记
}
```

**实现步骤**：
1. 在聊天区域右侧加一个可拖拽宽度的面板（初始 400px，可拖到 200-800px）
2. 从 AI 回复中提取 `[Preview:xxx](preview://xxx)` 链接
3. 预览类型：
   - **URL 预览**：用 `webview_flutter` 加载页面（注意 Windows 兼容性）
   - **文件预览**：读本地文件，代码高亮/图片/纯文本
   - **日志预览**：显示工具调用输出
4. 面板可折叠（点击 X 关闭或拖到最窄自动收）

**风险**：**高**。
- `webview_flutter` 在 Windows Desktop 上支持有限，可能需要平台通道
- 拖拽面板需要处理好 `GestureDetector` + `setState` 性能
- 与现有左右分栏布局（280px 侧边栏 + 聊天区）不冲突但需要调整 `Row` 布局

---

## 执行策略

### 不破坏原则

每一阶段完成后，运行以下回归检查：

```
[ ] _sendMessage() 正常发消息
[ ] SSE 流式回复正常
[ ] 多会话切换不卡顿
[ ] 会话创建/删除正常
[ ] 文件附件上传正常
[ ] 文件持久化不报错
[ ] 搜索框原有功能正常
```

### 依赖顺序

```
1.1 拖拽文件       ← 无依赖，可以单独做
1.2 剪贴板粘贴     ← 无依赖，可以单独做
1.3 模型切换       ← 无依赖，可以单独做
    ↓
2.1 会话搜索       ← 依赖 无
2.2 语音输入       ← 依赖 record 包 + 后端 /api/audio/transcribe
2.3 语音输出       ← 依赖 audioplayers 包 + 后端 /api/audio/speak
    ↓
3.1 工具调用展示   ← 依赖 后端 WS 支持
3.2 Cmd+K 面板     ← 依赖 1.3（模型切换）+ 无
3.3 侧边预览       ← 依赖 webview_flutter Windows 兼容性确认
```

### 推荐执行顺序

```
第一周：1.1 → 1.2 → 1.3    （简单，快速出成果）
第二周：2.1                （中等，本地数据）
第三周：2.2 → 2.3          （中等，需要后端确认接口可用）
待定：  3.1 → 3.2 → 3.3    （等前三个阶段稳定后讨论）
```

---

## 文件清单汇总

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/widgets/chat_drop_zone.dart` | **新增** | 拖拽文件遮罩组件 |
| `lib/widgets/model_switcher.dart` | **新增** | 模型选择下拉 |
| `lib/services/voice_service.dart` | **新增** | 语音录制+TTS |
| `lib/widgets/voice_input_button.dart` | **新增** | 录音按钮组件 |
| `lib/widgets/command_palette.dart` | **新增** | Cmd+K 命令面板 |
| `lib/widgets/preview_panel.dart` | **新增** | 侧边预览面板 |
| `lib/screens/chat_screen.dart` | **修改** | 增量添加功能（不重构） |
| `lib/services/gateway_service.dart` | **修改** | 新增模型/语音/WS API |
| `lib/services/local_db.dart` | **修改** | 新增 FTS5 搜索 |
| `lib/widgets/chat_message.dart` | **修改** | 添加 TTS 喇叭按钮 + 工具调用卡片 |
| `pubspec.yaml` | **修改** | 新增 `record` / `audioplayers` / `webview_flutter` |

---

*编制日期：2026-06-06*
*基于 Hermes Desktop v1.0.0 代码分析*
