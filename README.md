# RightMenuPlus

一款**纯原生 Swift + FinderSync** 编写的轻量级 macOS 访达（Finder）右键增强工具。  
安装包体积仅约 **1.3 MB**，零 Electron 依赖、零广告弹窗、完全开源可控，且**无需安装完整 Xcode**，仅凭 macOS 自带 Command Line Tools 即可一键编译安装。

---

## 功能特性

### 1. 新建文件
在任意文件夹或桌面空白处右键即可快速创建：
* 文本文件（`.txt`）
* Markdown 文档（`.md`，支持在设置窗口自定义默认模板内容）
* Word 文档（`.docx`）、Excel 表格（`.xlsx`）、PPT 演示文稿（`.pptx`）——生成符合 OOXML 标准的有效空白文档，WPS / Microsoft Office / iWork 均可正常打开
* 自定义文件名与扩展名（如 `main.py`、`config.json`、`script.sh`）
* 自动避免重名冲突，并在创建后自动在 Finder 中高亮选中

### 2. 在此处打开
自动检测本机已安装的终端、IDE 与阅读器，右键一键打开当前目录或选中文件：
* **终端**：Terminal、iTerm2、Warp、Ghostty、XTerminal
* **编辑器与工具**：QuickMD、VS Code、Cursor、Antigravity、PyCharm、WebStorm、IntelliJ IDEA、DataGrip、HBuilderX、Obsidian、WPS Office、TextEdit

### 3. 复制路径
* **复制完整路径**（支持多选，按行分隔）
* **复制终端安全转义路径**（自动处理空格与特殊字符，直接粘贴到终端即可使用）
* **复制文件名**

### 4. 实用文件操作
* **剪切 / 粘贴剪切的文件到此目录**：还原 Windows 风格的剪切移动体验
* **移动到 / 复制到**：一键发送到桌面、下载、文稿或任意自选文件夹
* **彻底删除…**：绕过废纸篓直接删除，附带系统级二次确认弹窗防误删
* **显示 / 隐藏系统隐藏文件**：一键切换 Finder 隐藏文件显示状态

### 5. 菜单栏助手与开机静默自启
* 轻量化菜单栏图标 + 原生 SwiftUI 设置界面，实时查看扩展状态与最近操作日志
* 内置**开机静默自启**开关（基于标准 `LaunchAgent`），登录后自动在后台驻留菜单栏，不弹窗口

---

## 环境要求

* macOS 13.0 及以上（支持 Apple Silicon 与 Intel）
* 已安装 Xcode Command Line Tools（如未安装，可先执行 `xcode-select --install`）

---

## 安装与使用步骤

### 1. 克隆仓库并一键编译安装

```bash
git clone https://github.com/yz20211314/RightMenuPlus.git
cd RightMenuPlus
chmod +x build.sh
./build.sh
```

`build.sh` 会自动完成以下步骤：
1. 生成原生应用图标（`AppIcon.icns`）
2. 使用 `swiftc` 编译宿主应用（`RightMenuPlus.app`）与 Finder 扩展（`RightMenuPlusExtension.appex`）
3. 执行本地 Ad-Hoc 代码签名并安装到 `/Applications/RightMenuPlus.app`
4. 通过 `lsregister` 与 `pluginkit` 注册并启用 Finder 扩展
5. 自动配置并启动开机静默自启（`~/Library/LaunchAgents/com.local.RightMenuPlus.plist`）

### 2. 确认 Finder 扩展已启用

构建脚本会自动尝试启用扩展。如果右键菜单尚未出现，请手动检查：
1. 打开 **系统设置 → 通用 → 登录项与扩展 → 访达扩展**（旧版系统为 **隐私与安全性 → 扩展 → 访达扩展**）
2. 勾选 **RightMenuPlus 右键扩展**
3. 若仍未刷新，可在终端执行一次 `killall Finder`

### 3. 开始使用

* 在桌面或任意 Finder 文件夹的空白处或文件上点击右键，即可看到 **新建文件、在此处打开、复制路径、剪切/粘贴、移动到/复制到、彻底删除、显示/隐藏隐藏文件** 等菜单项。
* 首次在“桌面 / 文稿 / 下载”目录执行新建或移动文件时，若 macOS 弹出文件夹访问权限提醒，点击一次 **“允许”** 即可。
* 点击顶部菜单栏图标 → **“打开设置与状态…”**，可以自定义新建 Markdown 的默认模板、查看操作日志，或随时开关**开机自动静默启动**。

---

## 卸载方法

如需彻底卸载，执行以下命令即可：

```bash
launchctl bootout "gui/$(id -u)/com.local.RightMenuPlus" 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.local.RightMenuPlus.plist
pkill -x RightMenuPlus 2>/dev/null || true
pkill -x RightMenuPlusExtension 2>/dev/null || true
pluginkit -r /Applications/RightMenuPlus.app/Contents/PlugIns/RightMenuPlusExtension.appex 2>/dev/null || true
rm -rf /Applications/RightMenuPlus.app
rm -rf ~/Library/Application\ Support/RightMenuPlus
```

---

## 项目结构

```text
RightMenuPlus/
├── build.sh                          # 一键编译、打包、签名、安装与自启配置脚本
├── Sources/
│   ├── Shared/ActionProtocol.swift   # 扩展与宿主 App 通信协议及常见应用清单
│   ├── App/
│   │   ├── RightMenuPlusApp.swift    # 菜单栏图标与 SwiftUI 设置界面
│   │   ├── ActionExecutor.swift      # 新建/剪切粘贴/移动/删除/打开/自启核心实现
│   │   └── OfficeTemplates.swift     # 标准 OOXML (.docx/.xlsx/.pptx) 空白文档生成器
│   └── Extension/
│       └── FinderSync.swift          # macOS FinderSync 右键菜单扩展
├── Resources/
│   ├── App-Info.plist                # 宿主应用配置
│   ├── Extension-Info.plist          # FinderSync 扩展配置
│   └── Extension.entitlements        # 扩展沙盒权限配置
└── Scripts/
    └── generate_icon.swift           # CoreGraphics 原生图标生成器
```

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
