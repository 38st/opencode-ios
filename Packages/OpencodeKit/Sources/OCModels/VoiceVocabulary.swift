import Foundation

/// Words the recognizer should favour in a session: file names, code symbols the conversation mentions, and agent
/// names. SpeechAnalyzer takes them as contextual strings.
public enum VoiceVocabulary {
    public static let limit = 100

    /// - Parameters:
    ///   - files: paths of the session's changed or mentioned files; each contributes its name and its stem.
    ///   - texts: recent conversation text; inline code spans that look like identifiers become symbols.
    public static func strings(files: [String], texts: [String], agents: [String], limit: Int = limit) -> [String] {
        var seen = Set<String>(), result: [String] = []
        func add(_ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2, value.count <= 60, seen.insert(value.lowercased()).inserted, result.count < limit else { return }
            result.append(value)
        }
        agents.forEach(add)
        for path in files {
            let name = (path as NSString).lastPathComponent
            add(name); add((name as NSString).deletingPathExtension)
        }
        for text in texts.reversed() {
            for symbol in symbols(in: text) { add(symbol) }
        }
        return result
    }
    /// Identifiers inside backticks: `ReadStore`, `send(_:)`, `user_id`.
    static func symbols(in text: String) -> [String] {
        var out: [String] = []
        let parts = text.split(separator: "`", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() where index % 2 == 1 {
            let candidate = part.split(separator: "(").first.map(String.init) ?? ""
            if candidate.range(of: #"^[A-Za-z_][A-Za-z0-9_.]{1,59}$"#, options: .regularExpression) != nil { out.append(candidate) }
        }
        return out
    }
}
