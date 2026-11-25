import Cocoa

final class AppStateStore: ObservableObject {
    static let shared = AppStateStore()

    @Published var recentLogs: [String] = []
    @Published var cutPaths: [String] = []
    @Published var extensionEnabled: Bool = false
    @Published var extensionRegistered: Bool = false
    @Published var launchAtLoginEnabled: Bool = false
    @Published var markdownTemplate: String {
        didSet {
            UserDefaults.standard.set(markdownTemplate, forKey: "markdownTemplate")
        }
    }

    private let cutboardURL: URL
    private let launchAgentURL: URL

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RightMenuPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.cutboardURL = supportDir.appendingPathComponent("cutboard.json")
        self.launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(RightMenuConstants.hostBundleID).plist")
        self.markdownTemplate = UserDefaults.standard.string(forKey: "markdownTemplate") ?? "# 新建文档\n\n"
        self.launchAtLoginEnabled = FileManager.default.fileExists(atPath: launchAgentURL.path)
        loadCutboard()
        refreshExtensionStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let uid = getuid()
        let domain = "gui/\(uid)"
        let label = RightMenuConstants.hostBundleID
        let fm = FileManager.default

        if enabled {
            let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
            try? fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [
                    "/Applications/RightMenuPlus.app/Contents/MacOS/RightMenuPlus",
                    "--background"
                ],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: launchAgentURL, options: .atomic)
            }
            let bootout = Process()
            bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootout.arguments = ["bootout", "\(domain)/\(label)"]
            try? bootout.run()
            bootout.waitUntilExit()

            let bootstrap = Process()
            bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootstrap.arguments = ["bootstrap", domain, launchAgentURL.path]
            try? bootstrap.run()
            bootstrap.waitUntilExit()

            DispatchQueue.main.async {
                self.launchAtLoginEnabled = fm.fileExists(atPath: self.launchAgentURL.path)
            }
            log("已开启开机静默自启")
        } else {
            let bootout = Process()
            bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            bootout.arguments = ["bootout", "\(domain)/\(label)"]
            try? bootout.run()
            bootout.waitUntilExit()

            try? fm.removeItem(at: launchAgentURL)
            DispatchQueue.main.async {
                self.launchAtLoginEnabled = false
            }
            log("已关闭开机静默自启")
        }
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = "[\(formatter.string(from: Date()))] \(message)"
        DispatchQueue.main.async {
            self.recentLogs.insert(entry, at: 0)
            if self.recentLogs.count > 50 {
                self.recentLogs.removeLast()
            }
        }
    }

    func saveCutPaths(_ paths: [String]) {
        DispatchQueue.main.async {
            self.cutPaths = paths
        }
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: cutboardURL, options: .atomic)
        }
    }

    func loadCutboard() {
        if let data = try? Data(contentsOf: cutboardURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.cutPaths = decoded
        }
    }

    func clearCutboard() {
        saveCutPaths([])
    }

    func refreshExtensionStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            proc.arguments = ["-m", "-v", "-i", RightMenuConstants.extensionBundleID]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let registered = output.contains(RightMenuConstants.extensionBundleID)
            let enabled = output.split(separator: "\n").contains { line in
                line.contains(RightMenuConstants.extensionBundleID) && line.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            }
            DispatchQueue.main.async {
                self.extensionRegistered = registered
                self.extensionEnabled = enabled
            }
        }
    }

    func enableExtensionViaPluginkit() {
        DispatchQueue.global(qos: .userInitiated).async {
            let appexPath = Bundle.main.bundleURL
                .appendingPathComponent("Contents/PlugIns/RightMenuPlusExtension.appex").path
            let addProc = Process()
            addProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            addProc.arguments = ["-a", appexPath]
            try? addProc.run()
            addProc.waitUntilExit()

            let useProc = Process()
            useProc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            useProc.arguments = ["-e", "use", "-i", RightMenuConstants.extensionBundleID]
            try? useProc.run()
            useProc.waitUntilExit()

            self.refreshExtensionStatus()
            self.log("已尝试注册并启用 Finder 扩展")
        }
    }
}

final class ActionExecutor {
    static let shared = ActionExecutor()
    private init() {}

    func handle(url: URL, showSettings: @escaping () -> Void) {
        guard url.scheme == RightMenuConstants.urlScheme,
              let host = url.host,
              let action = RightMenuAction(rawValue: host) else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let dir = queryItems.first(where: { $0.name == "dir" })?.value
        let paths = queryItems.filter({ $0.name == "path" }).compactMap(\.value)
        let ext = queryItems.first(where: { $0.name == "ext" })?.value
        let bundleID = queryItems.first(where: { $0.name == "bundleID" })?.value
        let dest = queryItems.first(where: { $0.name == "dest" })?.value

        switch action {
        case .newFile:
            guard let dir = dir, let ext = ext else { return }
            createNewFile(in: dir, ext: ext)
        case .newCustomFile:
            guard let dir = dir else { return }
            promptAndCreateCustomFile(in: dir)
        case .openTerminal:
            guard let dir = dir else { return }
            openInTerminal(dir: dir, bundleID: bundleID ?? "com.apple.Terminal")
        case .openWithApp:
            guard let bundleID = bundleID else { return }
            let targets = paths.isEmpty ? (dir.map { [$0] } ?? []) : paths
            openWithApp(targets: targets, bundleID: bundleID)
        case .cutFiles:
            guard !paths.isEmpty else { return }
            AppStateStore.shared.saveCutPaths(paths)
            AppStateStore.shared.log("已剪切 \(paths.count) 个项目，可在目标文件夹右键粘贴")
            NSSound(named: "Tink")?.play()
        case .pasteCutFiles:
            guard let dir = dir else { return }
            pasteCutFiles(into: dir)
        case .moveToFolder:
            guard let dest = dest, !paths.isEmpty else { return }
            transferFiles(paths: paths, to: dest, copy: false)
        case .copyToFolder:
            guard let dest = dest, !paths.isEmpty else { return }
            transferFiles(paths: paths, to: dest, copy: true)
        case .moveToChooseFolder:
            guard !paths.isEmpty else { return }
            chooseFolderAndTransfer(paths: paths, copy: false)
        case .copyToChooseFolder:
            guard !paths.isEmpty else { return }
            chooseFolderAndTransfer(paths: paths, copy: true)
        case .permanentDelete:
            guard !paths.isEmpty else { return }
            confirmAndPermanentDelete(paths: paths)
        case .toggleHiddenFiles:
            toggleHiddenFiles()
        case .openSettings:
            showSettings()
        }
    }

    // MARK: - New File
    private func createNewFile(in dirPath: String, ext: String) {
        let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
        let baseName: String
        switch ext.lowercased() {
        case "md": baseName = "未命名文档"
        case "docx": baseName = "未命名文档"
        case "xlsx": baseName = "未命名表格"
        case "pptx": baseName = "未命名演示文稿"
        default: baseName = "未命名文件"
        }

        let targetURL = uniqueURL(in: dirURL, baseName: baseName, ext: ext)
        do {
            try OfficeTemplateGenerator.createEmptyFile(
                ext: ext,
                at: targetURL,
                markdownTemplate: AppStateStore.shared.markdownTemplate
            )
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            AppStateStore.shared.log("已新建文件: \(targetURL.lastPathComponent)")
        } catch {
            showError(title: "新建文件失败", message: error.localizedDescription)
        }
    }

    private func promptAndCreateCustomFile(in dirPath: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "新建自定义文件"
        alert.informativeText = "请输入文件名（含扩展名，例如 notes.md、main.py、config.json）："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = "untitled.txt"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let rawName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty, !rawName.contains("/") else {
            showError(title: "无效文件名", message: "文件名不能为空且不能包含斜杠 (/)。")
            return
        }

        let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
        let fileURL = dirURL.appendingPathComponent(rawName)
        let ext = fileURL.pathExtension
        let finalURL = FileManager.default.fileExists(atPath: fileURL.path)
            ? uniqueURL(in: dirURL, baseName: fileURL.deletingPathExtension().lastPathComponent, ext: ext)
            : fileURL

        do {
            try OfficeTemplateGenerator.createEmptyFile(
                ext: ext,
                at: finalURL,
                markdownTemplate: AppStateStore.shared.markdownTemplate
            )
            NSWorkspace.shared.activateFileViewerSelecting([finalURL])
            AppStateStore.shared.log("已新建自定义文件: \(finalURL.lastPathComponent)")
        } catch {
            showError(title: "新建文件失败", message: error.localizedDescription)
        }
    }

    // MARK: - Open Terminal & External Apps
    private func openInTerminal(dir: String, bundleID: String) {
        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([dirURL], withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.showError(title: "打开终端失败", message: error.localizedDescription)
                    }
                }
            }
            AppStateStore.shared.log("已在终端打开: \(dir)")
            return
        }

        // Fallback via /usr/bin/open -a Terminal
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", dir]
        try? proc.run()
        AppStateStore.shared.log("已在 Terminal 打开: \(dir)")
    }

    private func openWithApp(targets: [String], bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            showError(title: "未找到应用", message: "无法找到应用 \(bundleID)。")
            return
        }
        let urls = targets.map { URL(fileURLWithPath: $0) }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.showError(title: "打开失败", message: error.localizedDescription)
                }
            }
        }
        AppStateStore.shared.log("已用 \(appURL.deletingPathExtension().lastPathComponent) 打开 \(urls.count) 项")
    }

    // MARK: - Cut / Paste / Move / Copy
    private func pasteCutFiles(into destDir: String) {
        AppStateStore.shared.loadCutboard()
        let paths = AppStateStore.shared.cutPaths
        guard !paths.isEmpty else {
            showInfo(title: "剪贴板为空", message: "请先在文件上右键选择“剪切”，再到目标目录粘贴。")
            return
        }
        transferFiles(paths: paths, to: destDir, copy: false)
        AppStateStore.shared.clearCutboard()
    }

    private func chooseFolderAndTransfer(paths: [String], copy: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = copy ? "选择复制目标文件夹" : "选择移动目标文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        transferFiles(paths: paths, to: folderURL.path, copy: copy)
    }

    private func transferFiles(paths: [String], to destDir: String, copy: Bool) {
        let fm = FileManager.default
        let destFolderURL = URL(fileURLWithPath: destDir, isDirectory: true)
        var movedURLs: [URL] = []

        for path in paths {
            let srcURL = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: srcURL.path) else { continue }
            if !copy && srcURL.deletingLastPathComponent().standardizedFileURL == destFolderURL.standardizedFileURL {
                continue
            }

            let targetURL = uniqueDestinationURL(in: destFolderURL, fileName: srcURL.lastPathComponent)
            do {
                if copy {
                    try fm.copyItem(at: srcURL, to: targetURL)
                } else {
                    try fm.moveItem(at: srcURL, to: targetURL)
                }
                movedURLs.append(targetURL)
            } catch {
                showError(title: copy ? "复制失败" : "移动失败", message: "\(srcURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !movedURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(movedURLs)
            AppStateStore.shared.log("\(copy ? "已复制" : "已移动") \(movedURLs.count) 项到 \(destFolderURL.lastPathComponent)")
        }
    }

    // MARK: - Permanent Delete
    private func confirmAndPermanentDelete(paths: [String]) {
        NSApp.activate(ignoringOtherApps: true)
        let names = paths.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n")
        let more = paths.count > 5 ? "\n…等共 \(paths.count) 个项目" : ""

        let alert = NSAlert()
        alert.messageText = "确定要彻底删除这 \(paths.count) 个项目吗？"
        alert.informativeText = "此操作将绕过废纸篓并立即删除，无法撤销：\n\n\(names)\(more)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "彻底删除")
        alert.addButton(withTitle: "取消")
        if let firstButton = alert.buttons.first {
            firstButton.hasDestructiveAction = true
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let fm = FileManager.default
        var deletedCount = 0
        for path in paths {
            do {
                try fm.removeItem(atPath: path)
                deletedCount += 1
            } catch {
                showError(title: "删除失败", message: "\(URL(fileURLWithPath: path).lastPathComponent): \(error.localizedDescription)")
            }
        }
        AppStateStore.shared.log("已彻底删除 \(deletedCount) 个项目")
    }

    // MARK: - Toggle Hidden Files
    private func toggleHiddenFiles() {
        let current = CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, "com.apple.finder" as CFString)
        let isShowing: Bool
        if let boolVal = current as? Bool {
            isShowing = boolVal
        } else if let strVal = current as? String {
            isShowing = strVal.lowercased() == "true" || strVal.lowercased() == "yes" || strVal == "1"
        } else {
            isShowing = false
        }

        let nextValue = !isShowing
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", nextValue ? "true" : "false"]
        try? proc.run()
        proc.waitUntilExit()

        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Finder"]
        try? restart.run()
        restart.waitUntilExit()

        AppStateStore.shared.log(nextValue ? "已开启显示隐藏文件" : "已关闭显示隐藏文件")
    }

    // MARK: - Helpers
    private func uniqueURL(in directory: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = ext.isEmpty
            ? directory.appendingPathComponent(baseName)
            : directory.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = ext.isEmpty
                ? directory.appendingPathComponent("\(baseName) \(index)")
                : directory.appendingPathComponent("\(baseName) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private func uniqueDestinationURL(in directory: URL, fileName: String) -> URL {
        let fm = FileManager.default
        let initial = directory.appendingPathComponent(fileName)
        if !fm.fileExists(atPath: initial.path) { return initial }
        let base = initial.deletingPathExtension().lastPathComponent
        let ext = initial.pathExtension
        return uniqueURL(in: directory, baseName: base, ext: ext)
    }

    private func showError(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func showInfo(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
}
