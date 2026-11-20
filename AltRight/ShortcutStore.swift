import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var settings = ShortcutSettings.standard
    @Published private(set) var conflict: String?

    private init() {}

    func load() {
        settings = ShortcutConfig.load()
    }

    /// Applies a new combination. Returns false when another command already
    /// uses it; the caller keeps listening so the user can simply press
    /// something else.
    @discardableResult
    func set(_ shortcut: Shortcut, for action: ShortcutAction) -> Bool {
        if let owner = settings.action(using: shortcut), owner != action {
            conflict = String(
                format: L("%@ already uses that shortcut."),
                owner.title
            )
            return false
        }

        conflict = nil
        settings[action] = shortcut
        persist()
        return true
    }

    func reset() {
        settings = .standard
        conflict = nil
        persist()
    }

    private func persist() {
        ShortcutConfig.save(settings)
        GlobalHotKeys.shared.apply(settings)
    }
}

extension Shortcut {
    /// The combination captured by the recorder. Returns nil for Escape,
    /// modifier-only presses, and keys that cannot be written as a menu
    /// equivalent.
    init?(event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else { return nil }
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        let key: String
        if CharacterSet.controlCharacters.contains(scalar) {
            // Control+letter arrives as a control character (⌃H as 0x08, for
            // example). Map 0x01…0x1A back to A…Z so the usual modifier
            // combinations can be recorded.
            guard scalar.value >= 1, scalar.value <= 26,
                  let letter = UnicodeScalar(scalar.value + 64) else {
                return nil
            }
            key = String(Character(letter))
        } else {
            key = characters.uppercased()
        }

        let modifiers = Shortcut.carbonModifiers(event.modifierFlags)
        guard modifiers != 0 else { return nil }

        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            key: key
        )
    }

    var swiftUIKey: KeyEquivalent {
        guard key.count == 1, let character = key.lowercased().first else {
            return "b"
        }
        return KeyEquivalent(character)
    }

    var swiftUIModifiers: SwiftUI.EventModifiers {
        var flags: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}

extension Shortcut {
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
