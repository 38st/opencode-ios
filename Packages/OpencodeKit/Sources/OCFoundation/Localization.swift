import Foundation
import Synchronization

/// User-facing strings live in each module's String Catalog (`Resources/Localizable.xcstrings`). `Bundle.module` is
/// internal to a module, so every module with strings declares a two-line `localized(_:comment:)` that calls
/// `string(_:bundle:comment:)` here. Code, paths, server data and terminal output are never looked up.
public enum OCLocalization {
    public enum Mode: Sendable, Equatable {
        case standard
        /// Every looked-up string appears twice, to find clipped and overlapping text before a translation does.
        case doubleLength
    }

    private static let state = Mutex(Mode.standard)

    public static var mode: Mode {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    public static func string(_ key: String.LocalizationValue, bundle: Bundle, comment: StaticString?) -> String {
        let value = String(localized: key, bundle: bundle, comment: comment)
        return mode == .doubleLength ? doubled(value) : value
    }

    static func doubled(_ value: String) -> String { value.isEmpty ? value : value + " " + value }
}
