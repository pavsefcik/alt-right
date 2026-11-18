import AppKit
import ApplicationServices

/// Drives Finder for the two actions that cannot be done from a sandboxed extension.
@MainActor
enum FinderActuator {
    static func perform(_ action: FinderAction) {
        switch action {
        case .copyPath:
            copyPath()
        case .pastePath:
            pastePath()
        case .goToFolder:
            goToFolder()
        case .connectToServer:
            connectToServer()
        case .openSettings:
            AppDelegate.shared?.showSettings()
        }
    }

    // MARK: - Copy Path (⌥⌘C)

    /// Lets Finder copy the paths itself. Handy from the menu bar, including in
    /// File Provider locations (iCloud Drive, Google Drive, …), where Finder Sync
    /// menus are never shown.
    private static func copyPath() {
        guard Permissions.hasAccessibility else {
            showAccessibilityAlert()
            return
        }

        let pasteboard = NSPasteboard.general
        let changeCountBeforeCopy = pasteboard.changeCount

        activateFinder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Keys.press(.c, flags: [.maskCommand, .maskAlternate])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard pasteboard.changeCount != changeCountBeforeCopy,
                  let text = pasteboard.string(forType: .string) else {
                return
            }

            let paths = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !paths.isEmpty {
                BookmarkCoordinator.shared.recordHistory(paths: paths)
            }
        }
    }

    // MARK: - Paste Path (⇧⌘G)

    /// Opens Finder's *Go to Folder* sheet and pastes the clipboard path there. It
    /// deliberately does not press Return: the user checks the destination and
    /// confirms with Return, exactly like Finder's own shortcut.
    private static func pastePath() {
        guard clipboardText() != nil else {
            NSSound.beep()
            return
        }

        guard Permissions.hasAccessibility else {
            showAccessibilityAlert()
            return
        }

        activateFinder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Keys.press(.g, flags: [.maskCommand, .maskShift])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                // Finder keeps the last path in "Go to Folder", so paste explicitly.
                Keys.press(.v, flags: [.maskCommand])
            }
        }
    }

    private static func clipboardText() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return raw
    }

    // MARK: - Go to Folder (⇧⌘G)

    /// Opens Finder's *Go to Folder* sheet without touching the clipboard.
    private static func goToFolder() {
        guard Permissions.hasAccessibility else {
            showAccessibilityAlert()
            return
        }

        activateFinder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Keys.press(.g, flags: [.maskCommand, .maskShift])
        }
    }

    // MARK: - Connect to Server (⌘K)

    private static func connectToServer() {
        guard Permissions.hasAccessibility else {
            showAccessibilityAlert()
            return
        }

        activateFinder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Keys.press(.k, flags: [.maskCommand])
        }
    }

    // MARK: - Helpers

    private static func activateFinder() {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return }

        if #available(macOS 14.0, *) {
            finder.activate()
        } else {
            finder.activate(options: [.activateAllWindows])
        }
    }

    private static func showAccessibilityAlert() {
        showAlert(
            title: L("Accessibility Access Needed"),
            message: L("Alt Right needs Accessibility access to press Finder shortcuts for you.\n\nOpen System Settings › Privacy & Security › Accessibility and enable Alt Right."),
            openSettings: {
                // This also adds Alt Right to the Accessibility list, so the user
                // only has to flip the switch.
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
        )
    }

    private static func showAlert(title: String, message: String, openSettings: (() -> Void)? = nil) {
        AppActivation.activate()

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        if openSettings != nil {
            alert.addButton(withTitle: L("Open System Settings"))
            alert.addButton(withTitle: L("OK"))
        } else {
            alert.addButton(withTitle: L("OK"))
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let openSettings {
            openSettings()
        }
    }
}

// MARK: - Keyboard

private enum Keys: CGKeyCode, CaseIterable {
    case c = 8
    case g = 5
    case v = 9
    case k = 40

    static func press(_ key: Keys, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let down = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        usleep(12_000)

        let up = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}
