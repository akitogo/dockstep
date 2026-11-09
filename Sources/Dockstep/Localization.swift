import Foundation

/// Looks up the translation for an English UI text.
/// Translations live in `Resources/<language>.lproj/Localizable.strings`; the English text is the key,
/// so a missing translation simply shows the English text.
func L(_ english: String) -> String {
    NSLocalizedString(english, comment: "")
}
