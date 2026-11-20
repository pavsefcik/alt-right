import AppKit
import Carbon.HIToolbox
import Foundation

/// The three commands whose shortcuts can be changed. Raw values are the stable
/// keys of the JSON file that is shared with the Finder extension.
enum ShortcutAction: String, CaseIterable, Codable, Hashable {
    case searchBookmarks
    case addBookmark
    case history

    var title: String {
        switch self {
        case .searchBookmarks: return L("Search Bookmarks")
        case .addBookmark: return L("Add Bookmark")
        case .history: return L("History")
        }
    }
}

/// One key combination, stored in Carbon terms because that is what the global
/// hot-key registration uses. `key` is only for display and menu equivalents.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    func matches(_ other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}

struct ShortcutSettings: Codable, Equatable {
    var searchBookmarks: Shortcut
    var addBookmark: Shortcut
    var history: Shortcut

    static let standard = ShortcutSettings(
        searchBookmarks: Shortcut(
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(cmdKey | optionKey),
            key: "B"
        ),
        addBookmark: Shortcut(
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(cmdKey | optionKey | shiftKey),
            key: "B"
        ),
        history: Shortcut(
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: UInt32(cmdKey | controlKey),
            key: "H"
        )
    )

    subscript(action: ShortcutAction) -> Shortcut {
        get {
            switch action {
            case .searchBookmarks: return searchBookmarks
            case .addBookmark: return addBookmark
            case .history: return history
            }
        }
        set {
            switch action {
            case .searchBookmarks: searchBookmarks = newValue
            case .addBookmark: addBookmark = newValue
            case .history: history = newValue
            }
        }
    }

    func action(using shortcut: Shortcut) -> ShortcutAction? {
        ShortcutAction.allCases.first { self[$0].matches(shortcut) }
    }
}

/// Reads and writes the shortcut settings.
///
/// The Finder extension is sandboxed and cannot see the app's Application
/// Support folder, so the app also broadcasts the settings over the distributed
/// notification centre. The extension keeps the last broadcast in its own
/// defaults and falls back to the standard shortcuts until it hears from the
/// app.
enum ShortcutConfig {
    static let cacheKey = "shortcuts"
    static let changedNotification = "com.pavel.altright.shortcutsChanged"
    static let requestNotification = "com.pavel.altright.shortcutsRequest"

    static func appURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return base
            .appendingPathComponent("Alt Right", isDirectory: true)
            .appendingPathComponent("shortcuts.json", isDirectory: false)
    }

    static func load() -> ShortcutSettings {
        if let settings = decode(at: appURL()) {
            return settings
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let settings = try? JSONDecoder().decode(ShortcutSettings.self, from: data) {
            return settings
        }
        return .standard
    }

    static func save(_ settings: ShortcutSettings) {
        write(settings, to: appURL())
        broadcast(settings)
    }

    /// App side: answer the extension's request and announce the current
    /// settings once at launch, so an extension that started first catches up.
    static func startServingChanges() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: NSNotification.Name(requestNotification),
            object: nil,
            queue: .main
        ) { _ in
            broadcast(load())
        }
        broadcast(load())
    }

    /// Extension side: remember every broadcast locally. UserDefaults inside
    /// the extension container survives restarts of the Finder extension.
    static func startObservingChanges() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: NSNotification.Name(changedNotification),
            object: nil,
            queue: .main
        ) { notification in
            guard let json = notification.userInfo?["settings"] as? String,
                  let data = json.data(using: .utf8),
                  let settings = try? JSONDecoder().decode(ShortcutSettings.self, from: data)
            else {
                return
            }
            UserDefaults.standard.set(data, forKey: cacheKey)
            _ = settings
        }

        center.postNotificationName(
            NSNotification.Name(requestNotification),
            object: nil
        )
    }

    private static func broadcast(_ settings: ShortcutSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(changedNotification),
            object: nil,
            userInfo: ["settings": json],
            deliverImmediately: true
        )
    }

    private static func decode(at url: URL) -> ShortcutSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShortcutSettings.self, from: data)
    }

    private static func write(_ settings: ShortcutSettings, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Alt Right: could not save shortcuts to \(url.path): \(error)")
        }
    }
}
