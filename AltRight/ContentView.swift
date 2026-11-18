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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            setupCard
            bookmarksCard
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            status.refresh()
            status.start()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Alt Right")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(L("Copy paths, jump to paths, and connect to servers — straight from Finder’s context menu."))
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
                Text(String(format: L("%d bookmarks"), bookmarks.bookmarks.count))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Button(L("Search Bookmarks…")) {
                    BookmarkCoordinator.shared.showSearch()
                }
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text(String(format: L("%d copied paths"), history.entries.count))
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Button(L("History")) {
                    BookmarkCoordinator.shared.showHistory()
                }
                .controlSize(.small)
            }

            Divider()

            HStack(spacing: 8) {
                Button(L("Open Data Folder")) {
                    NSWorkspace.shared.open(bookmarks.dataFolderURL)
                }
                .controlSize(.small)

                Button(L("Reveal Data File")) {
                    NSWorkspace.shared.activateFileViewerSelecting([bookmarks.fileURL])
                }
                .controlSize(.small)

                Spacer(minLength: 0)

                Button(L("Reload")) {
                    bookmarks.load()
                    history.load()
                }
                .controlSize(.small)
            }
        }
        .onAppear {
            bookmarks.load()
            history.load()
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

            Divider()

            StatusRow(
                symbol: status.hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                title: L("Accessibility"),
                state: status.hasAccessibility ? L("Granted") : L("Needed"),
                isGood: status.hasAccessibility,
                actionTitle: status.hasAccessibility ? nil : L("Grant…"),
                action: status.requestAccessibility
            )

            Text(L("Accessibility lets Alt Right press ⇧⌘G and ⌘K for you."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button(L("Restart Finder")) {
                    ExtensionStatus.restartFinder()
                }
                .controlSize(.small)
            }
        }
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
                    .controlSize(.small)
            }
        }
    }
}

struct MenuBarView: View {
    var body: some View {
        Button(L("Search Bookmarks…")) {
            DispatchQueue.main.async {
                BookmarkCoordinator.shared.showSearch()
            }
        }

        Button(L("Add Bookmark…")) {
            DispatchQueue.main.async {
                BookmarkCoordinator.shared.presentNewBookmark()
            }
        }

        Divider()

        Button(L("Copy Path")) { run(.copyPath) }
            .keyboardShortcut("c", modifiers: [.command, .option])

        // Paste Path is a convenience over “Go to Folder”: it also pastes the
        // clipboard, so it has no shortcut of its own.
        Button(L("Paste Path")) { run(.pastePath) }

        Button(L("History")) {
            DispatchQueue.main.async {
                BookmarkCoordinator.shared.showHistory()
            }
        }

        Button(L("Go to Folder") + "…") { run(.goToFolder) }
            .keyboardShortcut("g", modifiers: [.command, .shift])

        Button(L("Connect to Server") + "…") { run(.connectToServer) }
            .keyboardShortcut("k", modifiers: .command)

        Divider()

        Button(L("Open Alt Right…")) {
            // Let the menu-bar menu close before presenting the settings window.
            DispatchQueue.main.async {
                AppDelegate.shared?.showSettings()
            }
        }

        Divider()

        Button(L("Quit Alt Right")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Menu-bar menus close before the action runs, so give Finder a moment.
    private func run(_ action: FinderAction) {
        DispatchQueue.main.async {
            FinderActuator.perform(action)
        }
    }
}
