import AppKit
import ApplicationServices
import SwiftUI

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Spotlight on macOS 26 is an overlay: neither `NSWorkspace.frontmostApplication`
/// nor `CGWindowList` reports it. The system-wide focused accessibility element
/// is the reliable signal; the other checks stay as fallbacks.
enum SpotlightDetector {
    static func isActive() -> Bool {
        if isSpotlight(NSWorkspace.shared.frontmostApplication) {
            return true
        }
        if focusedElementBelongsToSpotlight() {
            return true
        }
        return spotlightWindowIsVisible()
    }

    static func isSpotlight(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""
        return bundleID.contains("spotlight") || name.contains("spotlight")
    }

    private static func focusedElementBelongsToSpotlight() -> Bool {
        guard Permissions.hasAccessibility else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let element = value else { return false }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success, pid > 0 else {
            return false
        }
        return isSpotlight(NSRunningApplication(processIdentifier: pid))
    }

    /// Older macOS versions expose the Spotlight overlay as a window owned by
    /// Spotlight. macOS 26 no longer does, but keeping the check costs little.
    private static func spotlightWindowIsVisible() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        for window in windows {
            let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() ?? ""
            guard owner.contains("spotlight") else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 0
            if layer > 0, alpha > 0.01 {
                return true
            }
        }
        return false
    }
}

enum ExtensionStatus {
    static let bundleIdentifier = "com.pavel.altright.FinderSync"

    /// Lines from `pluginkit -m` look like: `+    com.pavel.altright.FinderSync(1.0)`
    private static func lines() -> [String] {
        Shell.run("/usr/bin/pluginkit", ["-m", "-i", bundleIdentifier])
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains(bundleIdentifier) }
    }

    static var isRegistered: Bool {
        !lines().isEmpty
    }

    static var isEnabled: Bool {
        lines().contains { $0.hasPrefix("+") }
    }

    static func restartFinder() {
        Shell.run("/usr/bin/killall", ["Finder"])
    }
}

// MARK: - App info

enum AppInfo {
    /// Marketing version from the bundle, so the window cannot disagree with
    /// the build that is actually running. "v0.101.0", or "" if unreadable.
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let trimmed = short.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "v" + trimmed
    }
}

// MARK: - Panel chrome
//
// The bookmark, history and editor windows share one look: a rounded search
// field, small icon tiles in rows, and a bordered footer. Keeping them here —
// instead of a copy per window — is what stops the three drifting apart again.

/// Rounded search field with a magnifier and a clear button.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
                .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                    focus.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("Clear"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// Small transient confirmation shown over a panel after Copy. It never takes
/// clicks: the list stays usable while the message fades away.
struct CopyConfirmationToast: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(L("Copied"))
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color(nsColor: .labelColor).opacity(0.9))
        )
        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .allowsHitTesting(false)
    }
}

/// The little rounded tile a row puts in front of its text.
struct IconTile: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

/// The swatch a copied colour puts in front of its text — the same 24 pt
/// footprint as `IconTile`, so rows do not jump depending on what they hold.
/// The border keeps white and near-white colours visible against the panel, and
/// the checkerboard shows through anything partly transparent.
struct ColorSwatch: View {
    let color: ColorLiteral

    private let radius: CGFloat = 6

    var body: some View {
        ZStack {
            if color.alpha < 1 {
                Checkerboard()
            }

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: color.nsColor))
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .help(color.tooltip)
        .accessibilityLabel(color.hex)
    }

    /// Four-point squares under the fill, so `#FE92F580` reads as translucent
    /// instead of as a lighter colour.
    private struct Checkerboard: View {
        private let square: CGFloat = 4

        var body: some View {
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.white)
                )

                let columns = Int(ceil(size.width / square))
                let rows = Int(ceil(size.height / square))
                for row in 0..<rows {
                    for column in 0..<columns where (row + column).isMultiple(of: 2) {
                        let rect = CGRect(
                            x: CGFloat(column) * square,
                            y: CGFloat(row) * square,
                            width: square,
                            height: square
                        )
                        context.fill(
                            Path(rect),
                            with: .color(Color(nsColor: .quaternaryLabelColor))
                        )
                    }
                }
            }
        }
    }
}

/// Symbol for a saved path, so a folder does not look like a web link.
func pathSymbol(_ path: String) -> String {
    let lower = path.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
        return "globe"
    }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
        return isDirectory.boolValue ? "folder.fill" : "doc.fill"
    }
    return "questionmark.folder"
}

/// The rounded background every list row in the panel shares: the accent fill
/// for the click/keyboard selection, and a faint neutral fill whenever the
/// pointer is over the row. The hover flag lives in the modifier so each row
/// tracks its own pointer instead of the list keeping one global hover id.
struct ListRowHighlight: ViewModifier {
    var selected: Bool
    var cornerRadius: CGFloat = 7

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        if selected { return Color.accentColor.opacity(0.18) }
        return hovering ? Color.primary.opacity(0.07) : .clear
    }
}

extension View {
    /// `row.listRowHighlight(selected: id == selectedID)` — selection fill plus
    /// a hover fill that needs no click.
    func listRowHighlight(selected: Bool) -> some View {
        modifier(ListRowHighlight(selected: selected))
    }
}

// MARK: - Buttons

/// The one button look the app uses: a white fill and a hairline grey border on
/// a soft radius. AppKit's `.bordered` controls pick up the window's control
/// tint and read as flat grey blocks in a light popover; this keeps every
/// action the same weight and looks lighter than the panel behind it.
struct PanelButtonStyle: ButtonStyle {
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, role: role)
    }

    private struct StyleBody: View {
        let configuration: PanelButtonStyle.Configuration
        let role: ButtonRole?

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .frame(minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                )
                .opacity(configuration.isPressed ? 0.72 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }

        private var foreground: Color {
            guard isEnabled else { return Color.secondary.opacity(0.7) }
            if role == .destructive { return Color.red }
            return Color.primary
        }
    }
}

extension View {
    /// `Button { … } label: { … }.panelButtonStyle()` — the app-wide look.
    func panelButtonStyle(role: ButtonRole? = nil) -> some View {
        buttonStyle(PanelButtonStyle(role: role))
    }
}

/// The two neighbouring faces of the panel, drawn at the right end of every
/// footer: `‹ Copies` and `Paths ›`. The ring order is Bookmarks → Paths →
/// Copies → Bookmarks, so the left button is where the ← key goes and the
/// right button where Tab and → go.
struct ModeNavButtons: View {
    let previousTitle: String
    let nextTitle: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onPrevious) {
                HStack(spacing: 4) {
                    Chevron(direction: "chevron.left")
                    Text(previousTitle)
                }
            }
            .help(L("Press ← to switch"))

            Button(action: onNext) {
                HStack(spacing: 4) {
                    Text(nextTitle)
                    Chevron(direction: "chevron.right")
                }
            }
            .help(L("Press → to switch"))
        }
    }

    private struct Chevron: View {
        let direction: String

        var body: some View {
            Image(systemName: direction)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
