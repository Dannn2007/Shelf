# Shelf 🗄️

**A native macOS shelf for your files — organize by modules, never move the originals.**

Shelf is a lightweight, native SwiftUI app that lives in your Dock. It lets you
organize files into customizable "modules" (like `Study`, `Research`,
`Projects`…) using **shortcuts** — the actual files stay exactly where they are,
and you can always jump back to their real location in Finder with one click.

> 中文说明见下方 / Chinese docs below.

---

## Features

- **Modules** — create / rename (double-click) / delete / recolor modules, each
  with its own SF Symbol icon, accent / border / background colors
- **Shortcuts, not moves** — drop files in; only a bookmark is stored, the
  original file never moves
- **Jump back** — double-click to open the file, or reveal it in Finder
- **Auto-classification** — drop a file onto the right panel and Shelf suggests
  the best module (with confidence ring + matched-keyword reasons), plus
  alternates you can pick instead
- **Rule learning** — tick "remember this rule" and Shelf remembers
  `keyword → module` for next time
- **Optional AI boost** — plug in any OpenAI-compatible endpoint (DeepSeek by
  default) to enhance classification; fully offline without it
- **Notes & color tags** — annotate shortcuts, filter by tag
- **Menu bar + global hotkey** — default `⌥Space` to summon/hide, configurable
- **Custom theme** — global border & background colors, or follow the system
- **Temporary groups** — self-destructing modules (1h–24h) for short-lived clutter
- **Instant search** — ⌘F filters the current module by filename & note
- **Drag to move** — drop a tile onto another module in the sidebar to re-file it

## Requirements

- macOS 15.0 or newer
- Universal binary: Apple Silicon **and** Intel Macs

## Download (for everyone)

Grab `Shelf-v1.4.zip` from the [Releases](../../releases) page — no build tools needed.
The zip contains `Shelf.app` plus a full install & usage guide (Chinese).

> **First launch on a new Mac** (unsigned app): right-click Shelf → Open → Open again.
> If that doesn't work: System Settings → Privacy & Security → "Open Anyway",
> or run `xattr -cr /Applications/Shelf.app` in Terminal.

## Build from source

```bash
git clone https://github.com/Dannn2007/Shelf.git
cd Shelf
./Tools/build.sh      # swiftc, dual-arch + lipo → .build/Shelf.app (ad-hoc signed)
./Tools/install.sh    # copies to /Applications/Shelf.app
open /Applications/Shelf.app
```

## Project Layout

```
Sources/Shelf/
  App.swift            @main, AppDelegate, menu bar item, global hotkey
  Models.swift         ShelfModule / ShelfItem / tags / seed data
  Store.swift          persistence (JSON + bookmarks), global settings
  Classifier.swift     rule engine + optional AI classifier
  ContentView.swift    three-pane layout
  SidebarView.swift    module list, inline rename, module editor
  FileAreaView.swift   file grid, drag & drop, tiles
  InspectorView.swift  auto-classify drop panel
  DetailPanel.swift    selected-file details (note, tags, reveal)
  SettingsView.swift   general / appearance / AI / rules
Tools/
  build.sh             swiftc release build → .app bundle
  install.sh           install to /Applications
  make_icon.py         AppIcon generator (PIL)
```

## Documentation

- [安装与使用指南（中文）/ Install & Usage Guide](docs/USAGE.md)

## License

[MIT](LICENSE) © 2026 Danny Fan

---

# Shelf（中文说明）

**一个原生的 macOS 文件收纳架 —— 按模块整理文件，但永远不移动原文件。**

Shelf 常驻程序坞。你把文件拖进不同的模块（如 `Study`、`Work`、`Projects`），
它只保存**快捷方式**（bookmark），原文件待在原地不动；双击直接打开原文件，
一键跳回它在 Finder 中的位置。

### 功能

- **模块管理**：新建 / 双击重命名 / 删除，每个模块有独立图标、强调色、边框色、背景色
- **只存快捷方式**：拖进来的文件不会被移动
- **一键跳回**：双击打开，或「在 Finder 中显示」
- **自动分类**：把文件拖到右侧面板，给出首选（含置信度 + 命中理由）和次选，一键归档
- **规则学习**：勾选「记住这条规则」，下次同类文件自动优先归入
- **AI 增强（可选）**：默认对接 DeepSeek，兼容任意 OpenAI 格式接口；不填则纯本地规则
- **备注与彩色标签**：给快捷方式加备注、打标签、按标签筛选
- **菜单栏 + 全局快捷键**：默认 `⌥Space` 呼出/隐藏，可在设置修改
- **自定义外观**：全局边框色 / 背景色，或跟随系统深浅色
- **临时分组**：1-24 小时自动清理的模块，收纳短期杂物（原文件不受影响）
- **即时搜索**：⌘F 按文件名 / 备注过滤当前模块
- **拖拽归档**：按住文件磁贴拖到侧边栏另一个模块 = 直接移动归属

### 下载使用（不需要任何开发工具）

到 [Releases](../../releases) 页面下载 `Shelf-v1.4.zip`，解压后把 Shelf.app 拖进
「应用程序」即可。包内附完整中文《安装与使用指南》。

> **首次打开**可能被 macOS 拦截（App 未做 Apple 公证）：右键 Shelf → 打开 →
> 再点「打开」；若仍被拦，到 系统设置 → 隐私与安全性 → 点「仍要打开」，
> 或在终端执行 `xattr -cr /Applications/Shelf.app`。

### 构建要求

- macOS 15.0+，Universal 二进制（Apple Silicon 和 Intel 都支持）

### 构建与安装

```bash
git clone https://github.com/Dannn2007/Shelf.git
cd Shelf
./Tools/build.sh      # swiftc 编译 → .build/Shelf.app（ad-hoc 签名）
./Tools/install.sh    # 安装到 /Applications/Shelf.app
```

数据保存在 `~/Library/Application Support/Shelf/shelf.json`，删除 App 不会丢数据。
