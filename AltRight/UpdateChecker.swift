import AppKit
import Foundation

/// "Search for Updates" from the menu-bar menu. There is no bundled updater:
/// this asks GitHub for the latest release tag and points the user at the
/// download page when it is newer than the running build.
@MainActor
enum UpdateChecker {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/pavsefcik/alt-right/releases/latest"
    )!

    private static var isChecking = false

    static func check() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }

            do {
                var request = URLRequest(url: latestReleaseURL)
                request.setValue(
                    "application/vnd.github+json",
                    forHTTPHeaderField: "Accept"
                )
                request.setValue(
                    "Alt Right \(AppInfo.version)",
                    forHTTPHeaderField: "User-Agent"
                )
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw UpdateError.unexpectedResponse
                }

                let release = try JSONDecoder().decode(Release.self, from: data)
                present(release)
            } catch {
                presentFailure(error)
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        var version: String {
            tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        }
    }

    private enum UpdateError: LocalizedError {
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .unexpectedResponse:
                return L("GitHub did not return a release.")
            }
        }
    }

    private static func present(_ release: Release) {
        let current = AppInfo.version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let latest = release.version

        AppActivation.activate()

        guard isNewer(latest, than: current) else {
            let alert = NSAlert()
            alert.messageText = L("You’re Up to Date")
            alert.informativeText = String(
                format: L("Alt Right %@ is the latest version."),
                current.isEmpty ? "—" : current
            )
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = L("Update Available")
        alert.informativeText = String(
            format: L("Alt Right %@ is available. You have %@."),
            latest,
            current.isEmpty ? "—" : current
        )
        alert.addButton(withTitle: L("Download"))
        alert.addButton(withTitle: L("Later"))

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: release.htmlURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func presentFailure(_ error: Error) {
        AppActivation.activate()

        let alert = NSAlert()
        alert.messageText = L("Could Not Check for Updates")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    /// Numeric component comparison: 0.103.1 beats 0.102.9. A missing or
    /// non-numeric component counts as zero, so a tag like `v1.0.0-beta`
    /// still compares without crashing.
    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}
