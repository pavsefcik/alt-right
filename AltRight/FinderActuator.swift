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
        case .mergeWindows:
            mergeWindows()
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
        guard let raw = clipboardText() else {
            NSSound.beep()
            return
        }

        guard Permissions.hasAccessibility else {
            showAccessibilityAlert()
            return
        }

        // Finder's Go to Folder only understands a plain path. A quoted or
        // shell-escaped path would just beep there, and so would an `smb://`
        // URL, so put the cleaned form on the pasteboard before pasting it.
        if let normalized = Bookmark.normalizedPath(raw), normalized != raw {
            let pasteValue = Bookmark.isNetworkURL(normalized)
                ? (Bookmark.networkMountPath(normalized) ?? normalized)
                : normalized
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(pasteValue, forType: .string)
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

    // MARK: - Merge All Windows

    /// Folds every open Finder window into one window as tabs, using Finder's
    /// own *Merge All Windows* command. That command has no keyboard shortcut
    /// and lives only in Finder's Window menu, so it is reached through the
    /// accessibility tree by its stable identifier instead of its (localized)
    /// title.
    private static func mergeWindows() {
        guard Permissions.hasAccessibility else {
            showAccessibilityAlert()
            return
        }

        activateFinder()
        guard let finder = FinderAX.application else {
            NSSound.beep()
            return
        }

        // Finder needs a beat to come forward; the menu item's enabled state
        // follows the active windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let item = FinderAX.menuItem(
                in: finder,
                identifier: "mergeAllWindows:"
            ), FinderAX.isEnabled(item) else {
                // Nothing to merge (one window or fewer).
                NSSound.beep()
                return
            }
            FinderAX.press(item)
        }
    }

    // MARK: - Opening folders in tabs

    /// Opens a folder as a tab in Finder's frontmost window. Returns false when
    /// there is nothing to add a tab to, Accessibility is missing, or Finder's
    /// *New Tab* command cannot be found; the caller then opens a normal window.
    @discardableResult
    static func openFolderInNewTab(_ url: URL) -> Bool {
        guard Permissions.hasAccessibility,
              let finder = FinderAX.application,
              !FinderAX.windows(of: finder).isEmpty,
              let newTab = FinderAX.menuItem(
                  in: finder,
                  commandKey: "T",
                  modifiers: 0
              ) else {
            return false
        }

        activateFinder()
        FinderAX.press(newTab)

        // Finder creates the tab asynchronously. Once it exists it is the front
        // window; point it at the requested folder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            navigateFrontFinderWindow(to: url.path)
            activateFinder()
        }
        return true
    }

    private static func navigateFrontFinderWindow(to path: String) {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            set target of front window to POSIX file "\(escaped)"
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            NSLog("Alt Right: could not navigate the new Finder tab: \(error)")
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

// MARK: - Finder accessibility

/// Thin, read-only wrappers around Finder's accessibility tree. Only the parts
/// needed to reach menu commands are here; the tree is small and queried on
/// demand, never cached (Finder rebuilds its menus as windows come and go).
private enum FinderAX {
    static var application: AXUIElement? {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return nil }
        return AXUIElementCreateApplication(finder.processIdentifier)
    }

    static func windows(of application: AXUIElement) -> [AXUIElement] {
        elements(of: application, attribute: kAXWindowsAttribute)
    }

    static func isEnabled(_ item: AXUIElement) -> Bool {
        number(of: item, attribute: kAXEnabledAttribute)?.boolValue ?? true
    }

    static func press(_ item: AXUIElement) {
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    /// Finds a menu item by the stable accessibility identifier Finder gives
    /// it (for example `mergeAllWindows:`). Identifiers do not change with the
    /// system language.
    static func menuItem(
        in application: AXUIElement,
        identifier: String
    ) -> AXUIElement? {
        menuItems(of: application).first {
            string(of: $0, attribute: kAXIdentifierAttribute) == identifier
        }
    }

    /// Finds a menu item by its key equivalent. *New Tab* has ⌘T and no stable
    /// identifier, so the shortcut is the most durable way to recognize it.
    static func menuItem(
        in application: AXUIElement,
        commandKey: String,
        modifiers: Int
    ) -> AXUIElement? {
        menuItems(of: application).first { item in
            guard let key = string(of: item, attribute: kAXMenuItemCmdCharAttribute),
                  key.caseInsensitiveCompare(commandKey) == .orderedSame else {
                return false
            }
            let value = number(
                of: item,
                attribute: kAXMenuItemCmdModifiersAttribute
            )?.intValue
            return value == modifiers
        }
    }

    // MARK: Tree walking

    private static func menuItems(of application: AXUIElement) -> [AXUIElement] {
        guard let menuBar = element(
            of: application,
            attribute: kAXMenuBarAttribute
        ) else { return [] }

        var items: [AXUIElement] = []
        for barItem in elements(of: menuBar, attribute: kAXChildrenAttribute) {
            for menu in elements(of: barItem, attribute: kAXChildrenAttribute) {
                items.append(contentsOf: elements(
                    of: menu,
                    attribute: kAXChildrenAttribute
                ))
            }
        }
        return items
    }

    // MARK: Attribute access

    private static func element(
        of element: AXUIElement,
        attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(
        of element: AXUIElement,
        attribute: String
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success, let value else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func string(
        of element: AXUIElement,
        attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func number(
        of element: AXUIElement,
        attribute: String
    ) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? NSNumber
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
