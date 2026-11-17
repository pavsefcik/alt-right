import Foundation

/// Keys are the English text, so untranslated strings degrade to English.
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
}
