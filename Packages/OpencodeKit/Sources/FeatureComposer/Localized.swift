import Foundation
import OCFoundation

/// Looks up a user-facing string in this module's String Catalog (see `OCLocalization`).
nonisolated func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
    OCLocalization.string(key, bundle: .module, comment: comment)
}
