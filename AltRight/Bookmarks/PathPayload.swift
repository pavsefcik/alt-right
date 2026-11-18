import Foundation

/// Encodes the paths handed from the Finder extension to the main app in a URL.
enum PathPayload {
    static func encode(_ paths: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(paths) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> [String]? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        return paths
    }
}
