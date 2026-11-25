import Cocoa
import FinderSync

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    // Finder strips NSMenuItem.representedObject across XPC, but preserves `tag`.
    // Map each menu item's integer tag to its action closure.
    private var actionTable: [Int: () -> Void] = [:]
    private var nextTag: Int = 100

    override init() {
        super.init()
        let rootURL = URL(fileURLWithPath: "/")
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        FIFinderSyncController.default().directoryURLs = [rootURL, volumesURL]
    }

    override var toolbarItemName: String {
        return "RightMenuPlus"
    }

    override var toolbarItemToolTip: String {
        return "RightMenuPlus 右键增强菜单"
    }

    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "RightMenuPlus")
            ?? NSImage(named: NSImage.actionTemplateName)!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        actionTable.removeAll()
        nextTag = 100

        let menu = NSMenu(title: "RightMenuPlus")
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targetDirURL = resolveTargetDirectory(menuKind: menuKind, selectedURLs: selectedURLs)

        switch menuKind {
        case .contextualMenuForContainer, .contextualMenuForSidebar:
            addNewFileSubmenu(to: menu, targetDir: targetDirURL)
            addOpenWithSubmenu(to: menu, targetDir: targetDirURL, selectedURLs: [])
            if let dirPath = targetDirURL?.path {
                addActionItem(to: menu, title: "粘贴剪切的文件到此目录", symbol: "doc.on.clipboard") { [weak self] in
                    self?.dispatchToHost(action: .pasteCutFiles, dir: dirPath)
                }
                addActionItem(to: menu, title: "复制当前目录路径", symbol: "link") { [weak self] in
                    self?.copyToPasteboard(dirPath)
                }
            }
            addActionItem(to: menu, title: "显示 / 隐藏隐藏文件", symbol: "eye") { [weak self] in
                self?.dispatchToHost(action: .toggleHiddenFiles)
            }

        case .contextualMenuForItems:
            let itemPaths = selectedURLs.map(\.path)
            if targetDirURL != nil {
                addNewFileSubmenu(to: menu, targetDir: targetDirURL)
            }
            addCopyPathSubmenu(to: menu, paths: itemPaths)
            addOpenWithSubmenu(to: menu, targetDir: targetDirURL, selectedURLs: selectedURLs)
            addActionItem(to: menu, title: "剪切", symbol: "scissors") { [weak self] in
                self?.dispatchToHost(action: .cutFiles, paths: itemPaths)
            }
            addTransferSubmenu(to: menu, title: "移动到", symbol: "folder", paths: itemPaths, copy: false)
            addTransferSubmenu(to: menu, title: "复制到", symbol: "plus.rectangle.on.folder", paths: itemPaths, copy: true)
            addActionItem(to: menu, title: "彻底删除…", symbol: "trash") { [weak self] in
                self?.dispatchToHost(action: .permanentDelete, paths: itemPaths)
            }

        case .toolbarItemMenu:
            addNewFileSubmenu(to: menu, targetDir: targetDirURL)
            addOpenWithSubmenu(to: menu, targetDir: targetDirURL, selectedURLs: selectedURLs)
            if !selectedURLs.isEmpty {
                addCopyPathSubmenu(to: menu, paths: selectedURLs.map(\.path))
            } else if let dirPath = targetDirURL?.path {
                addActionItem(to: menu, title: "复制当前目录路径", symbol: "link") { [weak self] in
                    self?.copyToPasteboard(dirPath)
                }
            }
            addActionItem(to: menu, title: "显示 / 隐藏隐藏文件", symbol: "eye") { [weak self] in
                self?.dispatchToHost(action: .toggleHiddenFiles)
            }
            menu.addItem(.separator())
            addActionItem(to: menu, title: "打开 RightMenuPlus 设置…", symbol: "gearshape") { [weak self] in
                self?.dispatchToHost(action: .openSettings)
            }

        @unknown default:
            break
        }

        return menu
    }

    // MARK: - Unified XPC-Safe Action Dispatch
    @objc func performMenuAction(_ sender: NSMenuItem) {
        let tag = sender.tag
        if let handler = actionTable[tag] {
            handler()
        } else {
            NSLog("RightMenuPlusExtension: no action found for tag %ld (title: %@)", tag, sender.title)
        }
    }

    // MARK: - Submenu Builders
    private func addNewFileSubmenu(to parent: NSMenu, targetDir: URL?) {
        guard let dirPath = targetDir?.path else { return }
        let submenu = NSMenu(title: "新建文件")
        let templates: [(String, String, String)] = [
            ("文本文件 (.txt)", "txt", "doc.plaintext"),
            ("Markdown 文档 (.md)", "md", "doc.richtext"),
            ("Word 文档 (.docx)", "docx", "doc.text"),
            ("Excel 表格 (.xlsx)", "xlsx", "tablecells"),
            ("PPT 演示文稿 (.pptx)", "pptx", "play.rectangle")
        ]
        for (title, ext, symbol) in templates {
            addActionItem(to: submenu, title: title, symbol: symbol) { [weak self] in
                self?.dispatchToHost(action: .newFile, dir: dirPath, extra: ["ext": ext])
            }
        }
        submenu.addItem(.separator())
        addActionItem(to: submenu, title: "新建自定义文件…", symbol: "square.and.pencil") { [weak self] in
            self?.dispatchToHost(action: .newCustomFile, dir: dirPath)
        }

        let item = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        item.image = symbolImage("doc.badge.plus")
        item.submenu = submenu
        parent.addItem(item)
    }

    private func addOpenWithSubmenu(to parent: NSMenu, targetDir: URL?, selectedURLs: [URL]) {
        guard let dirPath = targetDir?.path else { return }
        let submenu = NSMenu(title: "在此处打开")

        var seenBundleIDs = Set<String>()
        for term in KnownExternalApps.terminals {
            guard !seenBundleIDs.contains(term.bundleID),
                  NSWorkspace.shared.urlForApplication(withBundleIdentifier: term.bundleID) != nil else {
                continue
            }
            seenBundleIDs.insert(term.bundleID)
            let bundleID = term.bundleID
            addActionItem(to: submenu, title: term.title, symbol: "terminal") { [weak self] in
                self?.dispatchToHost(action: .openTerminal, dir: dirPath, extra: ["bundleID": bundleID])
            }
        }

        let detectedEditors = KnownExternalApps.editors.filter { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
        }

        if !detectedEditors.isEmpty {
            submenu.addItem(.separator())
            let targets = selectedURLs.isEmpty ? [dirPath] : selectedURLs.map(\.path)
            for editor in detectedEditors {
                let bundleID = editor.bundleID
                addActionItem(to: submenu, title: editor.title, symbol: "app.badge") { [weak self] in
                    self?.dispatchToHost(action: .openWithApp, paths: targets, extra: ["bundleID": bundleID])
                }
            }
        }

        let item = NSMenuItem(title: "在此处打开", action: nil, keyEquivalent: "")
        item.image = symbolImage("terminal")
        item.submenu = submenu
        parent.addItem(item)
    }

    private func addCopyPathSubmenu(to parent: NSMenu, paths: [String]) {
        let submenu = NSMenu(title: "复制路径")
        addActionItem(to: submenu, title: "复制完整路径", symbol: "link") { [weak self] in
            self?.copyToPasteboard(paths.joined(separator: "\n"))
        }
        addActionItem(to: submenu, title: "复制终端安全路径", symbol: "terminal") { [weak self] in
            self?.copyToPasteboard(paths.map { ShellQuote.escape($0) }.joined(separator: " "))
        }
        addActionItem(to: submenu, title: "复制文件名", symbol: "textformat") { [weak self] in
            let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
            self?.copyToPasteboard(names.joined(separator: "\n"))
        }

        let item = NSMenuItem(title: "复制路径", action: nil, keyEquivalent: "")
        item.image = symbolImage("doc.on.clipboard")
        item.submenu = submenu
        parent.addItem(item)
    }

    private func addTransferSubmenu(to parent: NSMenu, title: String, symbol: String, paths: [String], copy: Bool) {
        let submenu = NSMenu(title: title)
        let home = realHomeDirectory()
        let quickDestinations: [(String, String, String)] = [
            ("桌面 (Desktop)", "\(home)/Desktop", "menubar.dock.rectangle"),
            ("下载 (Downloads)", "\(home)/Downloads", "arrow.down.circle"),
            ("文稿 (Documents)", "\(home)/Documents", "doc.on.doc")
        ]

        for (label, destPath, icon) in quickDestinations {
            addActionItem(to: submenu, title: label, symbol: icon) { [weak self] in
                self?.dispatchToHost(action: copy ? .copyToFolder : .moveToFolder, paths: paths, extra: ["dest": destPath])
            }
        }
        submenu.addItem(.separator())
        addActionItem(to: submenu, title: "选择其他文件夹…", symbol: "folder.badge.plus") { [weak self] in
            self?.dispatchToHost(action: copy ? .copyToChooseFolder : .moveToChooseFolder, paths: paths)
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = symbolImage(symbol)
        item.submenu = submenu
        parent.addItem(item)
    }

    // MARK: - Helpers
    private func addActionItem(to menu: NSMenu, title: String, symbol: String, handler: @escaping () -> Void) {
        let tag = nextTag
        nextTag += 1
        actionTable[tag] = handler

        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.image = symbolImage(symbol)
        menu.addItem(item)
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func resolveTargetDirectory(menuKind: FIMenuKind, selectedURLs: [URL]) -> URL? {
        if menuKind == .contextualMenuForItems, selectedURLs.count == 1, let first = selectedURLs.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
                return first
            }
            return first.deletingLastPathComponent()
        }
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return targeted
        }
        return selectedURLs.first?.deletingLastPathComponent()
    }

    private func realHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    private func dispatchToHost(action: RightMenuAction, dir: String? = nil, paths: [String] = [], extra: [String: String] = [:]) {
        guard let url = ActionURLBuilder.build(action: action, dir: dir, paths: paths, extra: extra) else { return }
        let payload = url.absoluteString

        // Always post immediately so a running host app handles it in <1ms with zero UI prompts.
        DistributedNotificationCenter.default().postNotificationName(
            RightMenuConstants.actionNotificationName,
            object: payload,
            userInfo: nil,
            deliverImmediately: true
        )

        // If host app is not running yet, launch it silently and re-deliver once ready.
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: RightMenuConstants.hostBundleID).isEmpty
        if !running, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: RightMenuConstants.hostBundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.arguments = ["--background"]
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    DistributedNotificationCenter.default().postNotificationName(
                        RightMenuConstants.actionNotificationName,
                        object: payload,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
