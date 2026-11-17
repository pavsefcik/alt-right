import AppKit

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
