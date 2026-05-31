# Hermes Skill Store (技能商店) 设计文档

## 1. 核心设计理念
技能商店旨在为 Hermes Agent 提供一个即插即用的插件市场。为了保证系统的开放性和稳定性，我们采用了 **“GitHub 驱动 + 静态 JSON 注册表 + 客户端拉取”** 的去中心化架构，而非传统的中心化后端 API。

## 2. 系统架构
### 2.1 注册表 (Registry)
*   **存储位置**：托管在 GitHub 公开仓库 `lovesmile/hermes-skills-registry`。
*   **索引文件**：`index.json` 包含了所有通过审核的技能元数据。
*   **同步机制**：
    *   **CDN 镜像策略**：客户端会并发/轮询多个镜像地址（GitHub 原生、jsDelivr、ghproxy 等）以解决国内网络访问 GitHub 慢的问题。
    *   **缓存穿透**：请求时附带毫秒级时间戳 `?t=ms`，强制绕过 CDN 缓存。

### 2.2 技能安装逻辑
支持两种主流安装模式：
1.  **独立仓库模式**：技能是一个完整的 Git 仓库，安装时直接 `git clone` 到 `~/.hermes/skills/` 下的对应分类目录。
2.  **Monorepo 模式**：多个技能共享一个大型仓库（如 `hermes-agent` 的官方技能包）。
    *   **提取逻辑**：克隆整个仓库到 `/tmp` -> 将指定的 `path` 子目录移动到目标位置 -> 清理临时文件。

## 3. 数据结构定义 (`RegistrySkill`)
每个技能在注册表中的定义如下：
```json
{
  "id": "weather-pro",
  "name": "Weather Pro",
  "description": "实时天气查询技能，支持全球城市。",
  "author": "HermesTeam",
  "version": "1.0.2",
  "category": "Tools",
  "stars": 128,
  "repo_url": "https://github.com/lovesmile/skill-weather.git",
  "path": "", 
  "readme": "SKILL.md"
}
```

## 4. 关键服务层实现 (`RegistryService`)
### 4.1 多镜像容灾算法
客户端维护一个候选 URL 列表，按优先级尝试加载：
1.  `raw.githubusercontent.com` (原源)
2.  `fastly.jsdelivr.net` (CDN 1)
3.  `gh-proxy.com` (代理)
4.  `cdn.staticaly.com` (CDN 2)

### 4.2 安装脚本分流
根据连接模式，安装命令由 `ConnectionManager` 路由：
*   **WSL/远程**：通过 `runShell` 执行 Linux 的 `mkdir`, `git clone`, `cp` 命令。
*   **内嵌模式**：调用 Windows 侧的 `git.exe`。

## 5. UI/UX 设计规范
### 5.1 页面布局
*   **双栏/双页签设计**：
    *   **“我的技能”**：列出 `~/.hermes/skills` 目录下已存在的 `SKILL.md`，支持即时卸载和跳转到聊天。
    *   **“发现商店”**：显示从注册表加载的网格列表。
*   **卡片设计**：网格布局，显示 Star 数、源码链接、以及紫色主题的安装按钮。

### 5.2 交互逻辑
*   **安装反馈**：点击安装后按钮进入 Loading 状态，成功后通过 SnackBar 提示。
*   **卸载保护**：二次确认弹窗。

## 6. 路径映射规则 (隔离设计)
为了支持不同模式，安装路径采用动态解析：
*   **Linux/WSL**: `~/.hermes/skills/<category>/<skill_id>`
*   **Windows (Embedded)**: `%APPDATA%\.hermes\skills\<category>\<skill_id>`

## 7. 后续扩展计划 (V1.1.0)
*   **版本自动检查**：对比已安装版本与注册表版本。
*   **依赖检测**：安装前自动执行 `pip install`。
*   **私有商店**：允许用户自定义注册表地址。
