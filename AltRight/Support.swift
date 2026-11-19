import AppKit
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
