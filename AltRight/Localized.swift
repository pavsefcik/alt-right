import Foundation

/// Localized string lookup. Keys *are* the English text, so a missing .strings entry
/// always falls back to readable English instead of a raw key.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
