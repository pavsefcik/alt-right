import AppKit
import ApplicationServices

enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    static let extensionsSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync"
    )

    static func openAccessibilitySettings() {
        if let url = accessibilitySettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    static func openExtensionsSettings() {
        if let url = extensionsSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
