import AppKit
import Carbon.HIToolbox
import Foundation

/// The commands whose shortcuts can be changed. Raw values are the stable keys
/// of the JSON file that is shared with the Finder extension.
enum ShortcutAction: String, CaseIterable, Codable, Hashable {
    case addBookmark
    case searchBookmarks
    case history
    case copies
    case pastePath
    case mergeWindows

    var title: String {
        switch self {
        case .addBookmark: return L("Add Bookmark")
        case .searchBookmarks: return L("Bookmarks")
        case .history: return L("Copied Paths")
        case .copies: return L("Copies")
        case .pastePath: return L("Paste Path")
        case .mergeWindows: return L("Merge All Windows")
        }
    }
}

/// Finder extension → app handoff for Add Bookmark when the app is already
/// running. The URL scheme is still used to launch a cold app.
enum AddBookmarkNotification {
    static let name = Notification.Name("com.pavel.altright.addBookmark")
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
    var addBookmark: Shortcut
    var searchBookmarks: Shortcut
    var history: Shortcut
    var copies: Shortcut
    var pastePath: Shortcut
    var mergeWindows: Shortcut

    static let standard = ShortcutSettings(
        addBookmark: Shortcut(
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(cmdKey | optionKey | shiftKey),
            key: "B"
        ),
        searchBookmarks: Shortcut(
            keyCode: UInt32(kVK_ANSI_B),
            modifiers: UInt32(cmdKey | optionKey),
            key: "B"
        ),
        history: Shortcut(
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: UInt32(cmdKey | controlKey),
            key: "H"
        ),
        copies: Shortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | controlKey),
            key: "C"
        ),
        pastePath: Shortcut(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(cmdKey | optionKey | shiftKey),
            key: "G"
        ),
        mergeWindows: Shortcut(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(cmdKey | controlKey),
            key: "M"
        )
    )

    private enum CodingKeys: String, CodingKey {
        case addBookmark
        case searchBookmarks
        case history
        case copies
        case pastePath
        case mergeWindows
    }

    init(
        addBookmark: Shortcut,
        searchBookmarks: Shortcut,
        history: Shortcut,
        copies: Shortcut,
        pastePath: Shortcut,
        mergeWindows: Shortcut
    ) {
        self.addBookmark = addBookmark
        self.searchBookmarks = searchBookmarks
        self.history = history
        self.copies = copies
        self.pastePath = pastePath
        self.mergeWindows = mergeWindows
    }

    /// Tolerant decoding: old files predate `addBookmark`, `copies`,
    /// `pastePath` and `mergeWindows`. Missing keys fall back to the standard
    /// combination instead of throwing the whole settings file away.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = ShortcutSettings.standard
        addBookmark = try container.decodeIfPresent(
            Shortcut.self,
            forKey: .addBookmark
        ) ?? standard.addBookmark
        searchBookmarks = try container.decodeIfPresent(
            Shortcut.self,
            forKey: .searchBookmarks
        ) ?? standard.searchBookmarks
        history = try container.decodeIfPresent(
            Shortcut.self,
            forKey: .history
        ) ?? standard.history
        copies = try container.decodeIfPresent(
            Shortcut.self,
            forKey: .copies
        ) ?? standard.copies
        pastePath = try container.decodeIfPresent(
            Shortcut.self,
            forKey: .pastePath
        ) ?? standard.pastePath
        mergeWindows = try container.decodeIfPresent(
            Shortcut.self,
            forKey: .mergeWindows
        ) ?? standard.mergeWindows
    }

    subscript(action: ShortcutAction) -> Shortcut {
        get {
            switch action {
            case .addBookmark: return addBookmark
            case .searchBookmarks: return searchBookmarks
            case .history: return history
            case .copies: return copies
            case .pastePath: return pastePath
            case .mergeWindows: return mergeWindows
            }
        }
        set {
            switch action {
            case .addBookmark: addBookmark = newValue
            case .searchBookmarks: searchBookmarks = newValue
            case .history: history = newValue
            case .copies: copies = newValue
            case .pastePath: pastePath = newValue
            case .mergeWindows: mergeWindows = newValue
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
