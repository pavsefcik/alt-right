import AppKit
import SwiftUI

/// Owns the menu-bar icon, the quick panel, and the classic menu behind a
/// right-click.
///
/// A `MenuBarExtra` with menu content cannot host a text field — a menu is not
/// a window you can type into — so the icon is a plain `NSStatusItem` and the
/// left-click surface is an `NSPopover`. The old command menu is still there on
/// right-click, built with AppKit because it has to outlive the SwiftUI scene.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = QuickPanelModel(
        store: .shared,
        historyStore: .shared,
        copyHistoryStore: .shared
    )

    /// The app that was frontmost when the panel opened, so Escape and a second
    /// click on the icon put focus back where the user came from.
    private var previousApp: NSRunningApplication?
    private var restoreFocusOnClose = false
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isShowingMenu = false

    /// A menu opened from inside the panel (the sort pop-up) tracks in its own
    /// window. While it is up, a dismissal request is remembered and replayed
    /// when the menu closes, so choosing a sort order never closes the panel.
    private var panelMenuIsTracking = false
    private var dismissalDeferredByMenu = false
    private var menuObservers: [NSObjectProtocol] = []

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "arrow.up.right",
                accessibilityDescription: L("Alt Right")
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = L("Alt Right")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let hosting = NSHostingController(
            rootView: QuickPanelView(
                model: model,
                // Saving the inline form finishes the errand: close the panel
                // and hand focus back to whatever the user came from.
                onEditorSaved: { [weak self] in
                    self?.closePanel(restoringFocus: true)
                }
            )
        )
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 600, height: 480)
        // Managed by hand instead of `.transient`: a transient popover can
        // close while the inline editor opens a file panel, and it did not
        // reliably dismiss on a click in another app. Deactivation closes it.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self

        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panelMenuIsTracking = true }
        })
        menuObservers.append(center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.panelMenuIsTracking = false
                guard self.dismissalDeferredByMenu else { return }
                self.dismissalDeferredByMenu = false
                // The held-back click really was outside the panel.
                self.closePanel()
            }
        })

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestClickAwayDismissal()
            }
        }
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: Any?) {
        guard !isShowingMenu else { return }

        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showClassicMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if popover.isShown {
            closePanel(restoringFocus: true)
            return
        }
        openPanelIfNeeded()
    }

    private func openPanelIfNeeded() {
        guard !popover.isShown else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        model.prepareForShow()
        presentPopover()
    }

    private func presentPopover() {
        guard let button = statusItem?.button else { return }

        AppActivation.activate()
        // Accessory apps can be asked to come forward without taking focus;
        // the panel's first click would then only activate it. Force it so the
        // search field and the sort menu are live immediately.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
        installKeyMonitor()
        installDismissMonitors()
    }

    // MARK: - Opening the panel for the app

    func showPanelBookmarks() {
        openPanelIfNeeded()
        model.showBookmarks()
        model.requestFocus()
    }

    func showPanelHistory() {
        openPanelIfNeeded()
        model.showHistory()
        model.requestFocus()
    }

    func showPanelCopyHistory() {
        openPanelIfNeeded()
        model.showCopyHistory()
        model.requestFocus()
    }

    func showPanelAddingBookmark(initialPath: String) {
        openPanelIfNeeded()
        // Keep whatever face is underneath: adding a bookmark from History
        // and cancelling returns to History, not to Bookmarks.
        model.presentEditor(existing: nil, initialPath: initialPath)
        model.requestFocus()
    }

    /// Reopens the panel (or reuses it) with the inline form showing. Used by
    /// the “Path Not Found” alert so Edit does not jump to another window.
    func showPanel(editing bookmark: Bookmark?) {
        openPanelIfNeeded()
        model.showBookmarks()
        model.presentEditor(
            existing: bookmark,
            initialPath: bookmark?.path ?? model.suggestedPath
        )
        model.requestFocus()
    }

    /// Closes the panel without restoring focus first, so opening a bookmark
    /// can hand focus to Finder/the browser instead of yanking it back.
    func closePanel(restoringFocus: Bool = false) {
        restoreFocusOnClose = restoringFocus
        guard popover.isShown else {
            restoreFocusOnClose = false
            return
        }
        popover.performClose(nil)
    }

    /// Dismissal from a click that landed outside the panel — unless a menu
    /// opened from inside the panel is still tracking, in which case the click
    /// belongs to the menu and the request waits until the menu closes.
    private func requestClickAwayDismissal() {
        guard popover.isShown, NSApp.modalWindow == nil else { return }
        if panelMenuIsTracking {
            dismissalDeferredByMenu = true
            return
        }
        closePanel()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.popover.isShown,
                  NSApp.modalWindow == nil,
                  event.window === self.popover.contentViewController?.view.window else {
                return event
            }

            // While the inline form is open its own fields and Save/Cancel
            // shortcuts own the keyboard. Escape only leaves the form.
            if self.model.editor != nil {
                if event.keyCode == 53 {
                    self.model.dismissEditor()
                    self.model.requestFocus()
                    return nil
                }
                return event
            }

            if event.keyCode == 53 { // Escape
                self.closePanel(restoringFocus: true)
                return nil
            }

            // Tab and → move to the next face. It is a local monitor, so
            // outside the panel Tab keeps its normal meaning.
            if event.keyCode == 48, // Tab
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                self.model.cycleMode()
                self.model.requestFocus()
                return nil
            }

            // ← and → walk the same ring as Tab. While the search field holds
            // text they keep their normal meaning and move the caret instead.
            if event.keyCode == 123 || event.keyCode == 124, // ← or →
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               !self.searchFieldHasText(in: event.window) {
                if event.keyCode == 123 {
                    self.model.cycleModeBackwards()
                } else {
                    self.model.cycleMode()
                }
                self.model.requestFocus()
                return nil
            }

            if self.model.mode == .history {
                switch event.specialKey {
                case .upArrow:
                    self.model.history.moveSelection(-1)
                    return nil
                case .downArrow:
                    self.model.history.moveSelection(1)
                    return nil
                case .carriageReturn, .newline, .enter:
                    self.openHistorySelected()
                    return nil
                default:
                    return event
                }
            }

            if self.model.mode == .copyHistory {
                switch event.specialKey {
                case .upArrow:
                    self.model.copyHistory.moveSelection(-1)
                    return nil
                case .downArrow:
                    self.model.copyHistory.moveSelection(1)
                    return nil
                case .carriageReturn, .newline, .enter:
                    self.copyHistorySelected()
                    return nil
                default:
                    return event
                }
            }

            switch event.specialKey {
            case .upArrow:
                self.model.moveSelection(-1)
                return nil
            case .downArrow:
                self.model.moveSelection(1)
                return nil
            case .carriageReturn, .newline, .enter:
                self.openSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// True while the panel's search field is editing text: the arrows then
    /// belong to the caret, not to the face switching.
    private func searchFieldHasText(in window: NSWindow?) -> Bool {
        guard let editor = window?.firstResponder as? NSTextView else { return false }
        return !editor.string.isEmpty
    }

    // MARK: - Click-away dismissal

    /// A click in another app (or on the desktop) never reaches a local
    /// monitor, and `.applicationDefined` means AppKit will not dismiss the
    /// panel by itself. Only global clicks are observed: clicks inside the
    /// panel (including its sort menu) must never dismiss it.
    private func installDismissMonitors() {
        guard globalMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestClickAwayDismissal()
            }
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        globalMouseMonitor = nil
    }

    private func openSelected() {
        guard model.editor == nil, let bookmark = model.selectedResult else {
            return
        }
        closePanel()
        model.open(
            bookmark,
            onEdit: { [weak self] in
                self?.showPanel(editing: bookmark)
            },
            onRemove: {
                BookmarkCoordinator.shared.removeBookmark(path: bookmark.path)
            }
        )
    }

    private func openHistorySelected() {
        guard let entry = model.history.selected else {
            NSSound.beep()
            return
        }
        closePanel()
        BookmarkOpener.open(path: entry.path)
    }

    /// Enter on a copy puts it back on the pasteboard and closes the panel, so
    /// the next ⌘V lands where the user was working.
    private func copyHistorySelected() {
        guard let entry = model.copyHistory.selected else {
            NSSound.beep()
            return
        }
        ClipboardWriter.write(entry.text)
        closePanel()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        model.requestFocus()
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        removeDismissMonitors()
        panelMenuIsTracking = false
        dismissalDeferredByMenu = false

        if restoreFocusOnClose {
            restoreFocusOnClose = false
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }

    // MARK: - Right-click menu

    private func showClassicMenu() {
        guard let item = statusItem, !isShowingMenu else { return }
        isShowingMenu = true
        defer { isShowingMenu = false }

        // A transient popover eats the mouse-down of the click that opens the
        // menu. Close it first, then let AppKit track the menu from the status
        // item; the old `popUpContextMenu(with:)` path flickered on the first
        // right-click because it started tracking on mouse-up.
        if popover.isShown {
            closePanel()
        }

        item.menu = buildClassicMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildClassicMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let shortcuts = ShortcutStore.shared.settings

        menu.addItem(shortcutItem(
            L("Add Bookmark"),
            action: #selector(addBookmarkFromMenu),
            shortcut: shortcuts.addBookmark
        ))

        menu.addItem(.separator())

        let copyPath = plainItem(L("Copy Path"), action: #selector(copyPathFromMenu))
        copyPath.keyEquivalent = "c"
        copyPath.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(copyPath)

        menu.addItem(shortcutItem(
            L("Paste Path"),
            action: #selector(pastePathFromMenu),
            shortcut: shortcuts.pastePath
        ))

        menu.addItem(shortcutItem(
            L("Go to Folder"),
            action: #selector(goToFolderFromMenu),
            shortcut: finderShortcut(key: "g", modifiers: [.command, .shift])
        ))

        menu.addItem(shortcutItem(
            L("Connect to Server"),
            action: #selector(connectToServerFromMenu),
            shortcut: finderShortcut(key: "k", modifiers: [.command])
        ))

        menu.addItem(.separator())

        menu.addItem(shortcutItem(
            L("Merge All Windows"),
            action: #selector(mergeWindowsFromMenu),
            shortcut: shortcuts.mergeWindows
        ))

        menu.addItem(.separator())

        let settings = plainItem(L("Settings…"), action: #selector(openSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        // macOS decorates a “Settings…” item with a gear on recent systems;
        // an explicitly blank image keeps the requested text-only menu.
        settings.image = NSImage(size: NSSize(width: 16, height: 16))
        menu.addItem(settings)

        menu.addItem(plainItem(L("Search for Updates…"), action: #selector(searchForUpdates)))

        menu.addItem(.separator())

        let quit = plainItem(L("Quit Alt Right"), action: #selector(quit))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        return menu
    }

    private func shortcutItem(
        _ title: String,
        action: Selector,
        shortcut: Shortcut
    ) -> NSMenuItem {
        let item = plainItem(title, action: action)
        item.keyEquivalent = shortcut.key.lowercased()
        item.keyEquivalentModifierMask = shortcut.eventModifiers
        return item
    }

    private func plainItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Finder's own shortcuts. They are display-only here: Finder receives the
    /// real keys, the menu is just showing what they are.
    private func finderShortcut(
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> Shortcut {
        Shortcut(
            keyCode: 0,
            modifiers: Shortcut.carbonModifiers(modifiers),
            key: key.uppercased()
        )
    }

    // MARK: - Menu actions

    @objc private func openSettings() {
        closePanel()
        DispatchQueue.main.async {
            AppDelegate.shared?.showSettings()
        }
    }

    @objc private func searchForUpdates() {
        closePanel()
        UpdateChecker.check()
    }

    @objc private func addBookmarkFromMenu() {
        closePanel()
        DispatchQueue.main.async {
            BookmarkCoordinator.shared.presentNewBookmark()
        }
    }

    @objc private func copyPathFromMenu() {
        runFinderAction(.copyPath)
    }
    @objc private func pastePathFromMenu() {
        runFinderAction(.pastePath)
    }

    @objc private func goToFolderFromMenu() {
        runFinderAction(.goToFolder)
    }

    @objc private func connectToServerFromMenu() {
        runFinderAction(.connectToServer)
    }
    @objc private func mergeWindowsFromMenu() {
        runFinderAction(.mergeWindows)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Menu-bar menus close before the action runs, so give Finder a moment.
    private func runFinderAction(_ action: FinderAction) {
        DispatchQueue.main.async {
            FinderActuator.perform(action)
        }
    }
}
