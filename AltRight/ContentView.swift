import Carbon.HIToolbox
import SwiftUI

@MainActor
final class StatusModel: ObservableObject {
    static let shared = StatusModel()

    @Published private(set) var extensionEnabled = false
    @Published private(set) var extensionRegistered = false
    @Published private(set) var hasAccessibility = false

    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        extensionEnabled = ExtensionStatus.isEnabled
        extensionRegistered = ExtensionStatus.isRegistered
        hasAccessibility = Permissions.hasAccessibility
    }

    func requestAccessibility() {
        Permissions.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }
}

struct ContentView: View {
    @ObservedObject private var status = StatusModel.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var copies = CopyHistoryStore.shared
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @AppStorage(OpenPreference.defaultsKey) private var openMode: OpenMode = .newWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            setupCard
            openingCard
            shortcutsCard
            bookmarksCard
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            status.refresh()
            status.start()
            shortcuts.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            // One mark for the whole app: an arrow pointing up and to the right,
            // nothing around it. Same glyph as the menu bar and the app icon.
            Image(systemName: "arrow.up.right")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Alt Right")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    if !AppInfo.version.isEmpty {
                        Text(AppInfo.version)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                Text(L("Manage paths, copies and bookmarks from your menu bar."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bookmarksCard: some View {
        Card(title: L("Bookmarks")) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .foregroundStyle(.secondary)
                Text(bookmarks.bookmarks.count == 1
                     ? String(format: L("%d bookmark"), 1)
                     : String(format: L("%d bookmarks"), bookmarks.bookmarks.count))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Button(L("Manage")) {
                    BookmarkCoordinator.shared.showSearch()
                }
                .buttonStyle(PanelButtonStyle())
            }

            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text(history.entries.count == 1
                     ? String(format: L("%d copied path"), 1)
                     : String(format: L("%d copied paths"), history.entries.count))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Button(L("Clear All")) {
                    history.clear()
                }
                .buttonStyle(PanelButtonStyle())
                .disabled(history.entries.isEmpty)
            }

            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
                Text(copies.entries.count == 1
                     ? String(format: L("%d copy"), 1)
                     : String(format: L("%d copies"), copies.entries.count))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Button(L("Clear All")) {
                    copies.clear()
                }
                .buttonStyle(PanelButtonStyle())
                .disabled(copies.entries.isEmpty)
            }
        }
        .onAppear {
            bookmarks.load()
            history.load()
            copies.load()
        }
    }

    private var shortcutsCard: some View {
        Card(title: L("Shortcuts")) {
            VStack(spacing: 10) {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRow(action: action, store: shortcuts)
                }

                if let conflict = shortcuts.conflict {
                    Text(conflict)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Text(L("Click a shortcut and press the new key combination."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button(L("Restore Defaults")) {
                        shortcuts.reset()
                    }
                    .buttonStyle(PanelButtonStyle())
                }
            }
        }
    }

    private var openingCard: some View {
        Card(title: L("Opening")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Open folders from bookmarks and copied paths in"))
                    .font(.system(size: 13, weight: .medium))

                Picker("", selection: $openMode) {
                    ForEach(OpenMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(L("New tabs require Accessibility access. Without it, folders open in a new window."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupCard: some View {
        Card(title: L("Setup")) {
            StatusRow(
                symbol: status.extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                title: L("Finder Extension"),
                state: status.extensionEnabled ? L("Enabled") : L("Off"),
                isGood: status.extensionEnabled,
                actionTitle: status.extensionEnabled ? nil : L("Turn On…"),
                action: Permissions.openExtensionsSettings
            )

            if !status.extensionEnabled {
                Text(L("In System Settings, turn on Alt Right under Extensions › Finder. If it is already on, quit and reopen Finder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            StatusRow(
                symbol: status.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                title: L("Accessibility"),
                state: status.hasAccessibility ? L("Granted") : L("Needed"),
                isGood: status.hasAccessibility,
                actionTitle: status.hasAccessibility ? nil : L("Grant…"),
                action: status.requestAccessibility
            )

            Text(L("Accessibility lets Alt Right press Finder shortcuts, merge windows and open tabs for you."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(L("Restart Finder")) {
                    ExtensionStatus.restartFinder()
                }
                .buttonStyle(PanelButtonStyle())
            }
        }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(action.title)
                .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 8)

            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? L("Press keys…") : store.settings[action].display)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 92)
            }
            .buttonStyle(PanelButtonStyle())
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        recording ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var symbol: String {
        switch action {
        case .addBookmark: return "plus.circle"
        case .searchBookmarks: return "magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        case .pastePath: return "doc.on.clipboard"
        case .mergeWindows: return "rectangle.on.rectangle"
        }
    }

    private func startRecording() {
        stopRecording()
        recording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing anything.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            guard let shortcut = Shortcut(event: event) else {
                NSSound.beep()
                return nil
            }

            if store.set(shortcut, for: action) {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
    }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct StatusRow: View {
    let symbol: String
    let title: String
    let state: String
    let isGood: Bool
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(isGood ? .green : .orange)
                .font(.system(size: 15))

            Text(title)
                .font(.system(size: 13, weight: .medium))

            Text(state)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(PanelButtonStyle())
            }
        }
    }
}
