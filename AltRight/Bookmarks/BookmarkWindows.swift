import AppKit
import SwiftUI

@MainActor
final class BookmarkSearchWindowController: NSWindowController {
    private let store: BookmarkStore

    init(store: BookmarkStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Bookmarks")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AltRightBookmarks")
        window.center()

        super.init(window: window)

        window.contentViewController = NSHostingController(
            rootView: BookmarkSearchView(store: store)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class BookmarkEditorWindowController: NSWindowController {
    private let store: BookmarkStore

    init(store: BookmarkStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Add Bookmark")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(existing: Bookmark?, initialPath: String) {
        guard let window else { return }

        let view = BookmarkEditorView(
            store: store,
            existing: existing,
            initialPath: initialPath,
            onSave: { [weak self] _ in
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        window.contentViewController = NSHostingController(rootView: view)
        window.title = existing == nil ? L("Add Bookmark") : L("Edit Bookmark")
        window.setContentSize(NSSize(width: 470, height: 390))
        window.center()

        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("History")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AltRightHistory")
        window.center()

        super.init(window: window)

        window.contentViewController = NSHostingController(
            rootView: HistoryView(store: store)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
