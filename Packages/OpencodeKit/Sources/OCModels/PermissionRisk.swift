import Foundation

public enum PermissionRisk: String, Sendable, CaseIterable {
    case low, elevated, high
    public static func assess(_ request: PermissionRequest) -> Self {
        switch request.action {
        case "read", "glob", "grep", "list": return .low
        case "edit", "write", "patch", "apply_patch", "webfetch", "websearch": return .elevated
        case "shell", "bash":
            let resources = request.resources.joined(separator: "\n").lowercased()
            let highRisk = [#"\brm\b"#, #"\bsudo\b"#, #"\b(chmod|chown|mkfs|dd)\b"#, #"\bgit\s+(push|reset|clean)\b"#,
                            #"(curl|wget).*\|"#, #"\b(sh|bash|zsh)\s+-c\b"#, #">\s*/"#]
            return highRisk.contains { resources.range(of: $0, options: .regularExpression) != nil } ? .high : .elevated
        default: return .high
        }
    }
}
