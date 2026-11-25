import SwiftUI
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var launchedViaURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupDistributedActionObserver()
        AppStateStore.shared.refreshExtensionStatus()

        let startInBackground = CommandLine.arguments.contains("--background")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !self.launchedViaURL && !startInBackground {
                self.showSettingsWindow()
            }
        }
    }

    private func setupDistributedActionObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedAction(_:)),
            name: RightMenuConstants.actionNotificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc func handleDistributedAction(_ notification: Notification) {
        guard let urlString = notification.object as? String,
              let url = URL(string: urlString) else {
            return
        }
        DispatchQueue.main.async {
            ActionExecutor.shared.handle(url: url) {
                self.showSettingsWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        launchedViaURL = true
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        DispatchQueue.main.async {
            ActionExecutor.shared.handle(url: url) {
                self.showSettingsWindow()
            }
        }
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "RightMenuPlus")
                ?? NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "RightMenuPlus")
            button.toolTip = "RightMenuPlus 右键助手"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "打开设置与状态…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(withTitle: "打开系统“访达扩展”设置", action: #selector(openSystemExtensionSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 RightMenuPlus", action: #selector(quitApp), keyEquivalent: "q")
        item.menu = menu
        self.statusItem = item
    }

    @objc func openSettingsFromMenu() {
        showSettingsWindow()
    }

    @objc func openSystemExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let contentView = SettingsView(onOpenSystemSettings: { [weak self] in
                self?.openSystemExtensionSettings()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 575),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RightMenuPlus — macOS 右键增强助手"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: contentView)
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var store = AppStateStore.shared
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "contextualmenu.and.cursorarrow")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RightMenuPlus")
                        .font(.title2.bold())
                    Text("开源原生 macOS Finder 右键增强工具（纯 Swift / 零广告）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Extension status box
            GroupBox(label: Label("Finder 扩展状态", systemImage: "puzzlepiece.extension")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.extensionEnabled ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                            Text(store.extensionEnabled ? "已启用（可在 Finder 右键使用）" : (store.extensionRegistered ? "已注册，尚未启用" : "未注册"))
                                .font(.headline)
                        }
                        Text("路径：系统设置 → 通用 → 登录项与扩展 → 访达扩展 → 勾选 RightMenuPlus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        Button("一键注册并启用") {
                            store.enableExtensionViaPluginkit()
                        }
                        Button("打开系统设置") {
                            onOpenSystemSettings()
                        }
                    }
                }
                .padding(6)
            }

            // Launch at login toggle
            GroupBox(label: Label("启动设置", systemImage: "power")) {
                Toggle(isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开机自动静默启动（仅常驻菜单栏，不弹窗口）")
                        Text("通过 ~/Library/LaunchAgents/com.local.RightMenuPlus.plist 管理")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(6)
            }

            // Built-in features summary
            GroupBox(label: Label("已内置的右键功能", systemImage: "sparkles")) {
                VStack(alignment: .leading, spacing: 6) {
                    featureRow("doc.badge.plus", "新建文件", "TXT / Markdown / Word(.docx) / Excel(.xlsx) / PPT(.pptx) / 自定义文件名")
                    featureRow("terminal", "在此处打开", "自动识别 Terminal、XTerminal、iTerm2、PyCharm、WebStorm、QuickMD 等")
                    featureRow("doc.on.clipboard", "复制路径", "完整路径、终端安全转义路径、文件名（支持多选）")
                    featureRow("scissors", "实用文件操作", "剪切并粘贴、移动/复制到常用目录、彻底删除（带确认）、切换隐藏文件")
                }
                .padding(6)
            }

            // Markdown template editor
            GroupBox(label: Label("新建 Markdown 默认模板", systemImage: "doc.text")) {
                TextEditor(text: $store.markdownTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 68)
                    .padding(4)
            }

            // Activity logs
            GroupBox(label: HStack {
                Label("最近操作记录", systemImage: "clock")
                Spacer()
                Button("刷新状态") { store.refreshExtensionStatus() }
                    .buttonStyle(.link)
                    .font(.caption)
            }) {
                if store.recentLogs.isEmpty {
                    Text("暂无操作记录 — 在任意 Finder 窗口右键即可体验。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(store.recentLogs, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(4)
                    }
                    .frame(height: 75)
                }
            }
        }
        .padding(18)
        .frame(width: 540, height: 575)
    }

    private func featureRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(title).bold().frame(width: 82, alignment: .leading)
            Text(desc).foregroundColor(.secondary).font(.callout)
        }
    }
}

@main
struct RightMenuPlusMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
