import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts for the three bookmark commands.
///
/// Menu key equivalents only fire while a menu is open (and a Finder context
/// menu ignores them entirely), so the shortcuts shown next to Search
/// Bookmarks, Add Bookmark and History are registered as real hot keys here.
/// Changing them in the settings window re-registers them immediately.
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var settings = ShortcutSettings.standard

    /// 'ALTR'
    private let signature: OSType = 0x414C5452

    private init() {}

    func start() {
        guard handler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return OSStatus(eventNotHandledErr) }

                let hotKeys = Unmanaged<GlobalHotKeys>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                hotKeys.perform(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard status == noErr else {
            NSLog("Alt Right: could not install hot key handler (\(status))")
            return
        }

        apply(ShortcutConfig.load())
    }

    /// Replaces every registered combination. Called at launch and whenever the
    /// settings window changes one.
    func apply(_ settings: ShortcutSettings) {
        self.settings = settings
        unregister()

        register(settings.addBookmark, id: 4) {
            Task { @MainActor in
                // The hot key is used from wherever the user is working, so
                // saving hands focus back instead of leaving the panel up.
                BookmarkCoordinator.shared.presentNewBookmark(closeAfterSave: true)
            }
        }
        register(settings.searchBookmarks, id: 1) {
            Task { @MainActor in
                BookmarkCoordinator.shared.showSearch()
            }
        }
        register(settings.history, id: 2) {
            Task { @MainActor in
                BookmarkCoordinator.shared.showHistory()
            }
        }
        register(settings.pastePath, id: 3) {
            Task { @MainActor in
                FinderActuator.perform(.pastePath)
            }
        }
        register(settings.mergeWindows, id: 5) {
            Task { @MainActor in
                FinderActuator.perform(.mergeWindows)
            }
        }
    }

    private func unregister() {
        for ref in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
        actions.removeAll()
    }

    private func register(_ shortcut: Shortcut, id: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            NSLog(
                "Alt Right: shortcut \(shortcut.display) is unavailable (\(status))"
            )
            return
        }

        hotKeys.append(ref)
        actions[id] = action
    }

    private func perform(id: UInt32) {
        // Carbon delivers application hot keys on the main thread, but be
        // explicit: the actions open windows and touch AppKit.
        if Thread.isMainThread {
            actions[id]?()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.actions[id]?()
            }
        }
    }
}
