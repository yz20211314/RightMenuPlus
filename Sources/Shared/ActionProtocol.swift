import Foundation

enum RightMenuConstants {
    static let urlScheme = "rightmenuplus"
    static let hostBundleID = "com.local.RightMenuPlus"
    static let extensionBundleID = "com.local.RightMenuPlus.FinderSync"
    static let appDisplayName = "RightMenuPlus"
    static let actionNotificationName = Notification.Name("com.local.RightMenuPlus.action")
}

enum RightMenuAction: String {
    case newFile = "new-file"
    case newCustomFile = "new-custom-file"
    case openTerminal = "open-terminal"
    case openWithApp = "open-with-app"
    case cutFiles = "cut-files"
    case pasteCutFiles = "paste-cut-files"
    case moveToFolder = "move-to-folder"
    case copyToFolder = "copy-to-folder"
    case moveToChooseFolder = "move-to-choose-folder"
    case copyToChooseFolder = "copy-to-choose-folder"
    case permanentDelete = "permanent-delete"
    case toggleHiddenFiles = "toggle-hidden-files"
    case openSettings = "open-settings"
}

struct KnownExternalApp {
    let title: String
    let bundleID: String
    let isTerminal: Bool
}

enum KnownExternalApps {
    static let terminals: [KnownExternalApp] = [
        KnownExternalApp(title: "终端 (Terminal)", bundleID: "com.apple.Terminal", isTerminal: true),
        KnownExternalApp(title: "iTerm2", bundleID: "com.googlecode.iterm2", isTerminal: true),
        KnownExternalApp(title: "Warp", bundleID: "dev.warp.Warp-Stable", isTerminal: true),
        KnownExternalApp(title: "Ghostty", bundleID: "com.mitchellh.ghostty", isTerminal: true),
        KnownExternalApp(title: "XTerminal", bundleID: "cn.xterminal.www", isTerminal: true),
        KnownExternalApp(title: "XTerminal", bundleID: "com.xterminal.app", isTerminal: true)
    ]

    static let editors: [KnownExternalApp] = [
        KnownExternalApp(title: "QuickMD", bundleID: "pl.falami.studio.QuickMD", isTerminal: false),
        KnownExternalApp(title: "VS Code", bundleID: "com.microsoft.VSCode", isTerminal: false),
        KnownExternalApp(title: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", isTerminal: false),
        KnownExternalApp(title: "Antigravity", bundleID: "com.google.antigravity", isTerminal: false),
        KnownExternalApp(title: "PyCharm", bundleID: "com.jetbrains.pycharm", isTerminal: false),
        KnownExternalApp(title: "WebStorm", bundleID: "com.jetbrains.WebStorm", isTerminal: false),
        KnownExternalApp(title: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij", isTerminal: false),
        KnownExternalApp(title: "DataGrip", bundleID: "com.jetbrains.datagrip", isTerminal: false),
        KnownExternalApp(title: "HBuilderX", bundleID: "io.dcloud.HBuilderX", isTerminal: false),
        KnownExternalApp(title: "Obsidian", bundleID: "md.obsidian", isTerminal: false),
        KnownExternalApp(title: "WPS Office", bundleID: "com.kingsoft.wpsoffice.mac", isTerminal: false),
        KnownExternalApp(title: "文本编辑 (TextEdit)", bundleID: "com.apple.TextEdit", isTerminal: false)
    ]
}

enum ActionURLBuilder {
    static func build(
        action: RightMenuAction,
        dir: String? = nil,
        paths: [String] = [],
        extra: [String: String] = [:]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = RightMenuConstants.urlScheme
        components.host = action.rawValue
        var items: [URLQueryItem] = []
        if let dir = dir {
            items.append(URLQueryItem(name: "dir", value: dir))
        }
        for path in paths {
            items.append(URLQueryItem(name: "path", value: path))
        }
        for (key, value) in extra {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}

enum ShellQuote {
    static func escape(_ path: String) -> String {
        if path.isEmpty { return "''" }
        let safeChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-+")
        if path.unicodeScalars.allSatisfy({ safeChars.contains($0) }) {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
