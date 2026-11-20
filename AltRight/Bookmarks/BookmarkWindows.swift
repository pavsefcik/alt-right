import AppKit
import SwiftUI

/// A window that behaves like something the user summoned, not a document:
///
/// * it always opens on the Space/desktop that is active *right now*, instead of
///   appearing on the Space the app happened to launch on (or was last used on),
///   which for an accessory app with no windows reads as "nothing happened";
/// * it goes away when it loses focus — clicking anywhere else, another app or
///   another of our own windows — and on Escape.
///
/// Closing means `orderOut`, never `close`: the controllers are reused, and the
/// form state of a cancelled Add Bookmark should not survive into the next one.
final class SummonedWindow: NSWindow {
    /// When the window was last ordered front. AppKit's activation is
    /// asynchronous, so a window can be key for a moment and then lose focus
    /// again while the app is still coming forward — that is not the user
    /// clicking away, and it must not make the window flash and vanish.
    private(set) var summonedAt = Date.distantPast

    func summon() {
        summonedAt = Date()
        makeKeyAndOrderFront(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class BookmarkSearchWindowController: NSWindowController, NSWindowDelegate {
    private let store: BookmarkStore

    init(store: BookmarkStore) {
        self.store = store

        let window = SummonedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Bookmarks")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AltRightBookmarks")
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: BookmarkSearchView(store: store)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        AppActivation.activate()
        (window as? SummonedWindow)?.summon()
    }

    func windowDidResignKey(_ notification: Notification) {
        SummonedDismissal.dismissIfUnused(window)
    }
}

@MainActor
final class BookmarkEditorWindowController: NSWindowController, NSWindowDelegate {
    private let store: BookmarkStore

    init(store: BookmarkStore) {
        self.store = store

        let window = SummonedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("Add Bookmark")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.center()

        super.init(window: window)

        window.delegate = self
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
        (window as? SummonedWindow)?.summon()
    }

    func windowDidResignKey(_ notification: Notification) {
        SummonedDismissal.dismissIfUnused(window)
    }
}

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store

        let window = SummonedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("History")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AltRightHistory")
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: HistoryView(store: store)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        AppActivation.activate()
        (window as? SummonedWindow)?.summon()
    }

    func windowDidResignKey(_ notification: Notification) {
        SummonedDismissal.dismissIfUnused(window)
    }
}

/// Shared "lost focus → go away" rule.
enum SummonedDismissal {
    /// Open modal panels (the file browser) make the summoned window resign
    /// key. That is not the user leaving, so dismissal is paused meanwhile.
    private static var modalDepth = 0

    static func noteModalStart() {
        modalDepth += 1
    }

    static func noteModalEnd() {
        modalDepth = max(0, modalDepth - 1)
    }

    /// Focus leaving the window means one of two different things:
    ///
    /// * the user went somewhere else (another app, the desktop) — the window
    ///   has done its job and goes away;
    /// * focus moved to another of our own windows (Edit from the list, the
    ///   settings window) — that is the app working, not the user leaving, so
    ///   the window stays.
    ///
    /// Sheets and alerts that belong to the window are the third case: without
    /// that guard, confirming "Delete bookmarks?" would order the list out from
    /// under its own dialog.
    static func dismissIfUnused(_ window: NSWindow?) {
        guard modalDepth == 0, NSApp.modalWindow == nil else { return }
        guard let window, window.isVisible else { return }
        guard window.attachedSheet == nil else { return }

        // Ignore the activation race right after summoning.
        if let summoned = window as? SummonedWindow,
           Date().timeIntervalSince(summoned.summonedAt) < 0.4 {
            return
        }

        if NSApp.isActive,
           let key = NSApp.keyWindow,
           key !== window,
           key.isVisible {
            return
        }

        window.orderOut(nil)
    }
}
