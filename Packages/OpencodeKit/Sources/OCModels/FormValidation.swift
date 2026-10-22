import Foundation
import OCFoundation

/// Mirrors core/form.ts: conditions are AND-ed; missing dependencies fail both
/// eq and neq, and multiselect equality means membership.
public enum FormValidation {
    public static func activeAnswers(_ form: FormInfo, answers: [String: JSONValue]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for field in form.fields where !field.isFallback {
            let f = field.fields
            guard isActive(field, answers: result) else { continue }
            let fallback = field.type == "external" ? nil : f.defaultValue
            if let value = answers[f.key] ?? fallback, !value.isNull { result[f.key] = value }
        }
        return result
    }
    public static func isActive(_ field: FormField, answers: [String: JSONValue]) -> Bool {
        if field.type == "external" { return true }
        return field.fields.when.allSatisfy { condition in
            guard let answer = answers[condition.key], !answer.isNull, let value = condition.value else { return false }
            let equal = answer.arrayValue.map { $0.contains(value) } ?? (answer == value)
            switch condition.op { case "eq": return equal; case "neq": return !equal; default: return false }
        }
    }
    public static func visibleFields(_ form: FormInfo, answers: [String: JSONValue]) -> [FormField] {
        let active = activeAnswers(form, answers: answers)
        return form.fields.filter { $0.type == "external" || (!$0.fields.hidden && isActive($0, answers: active)) }
    }
    public static func errors(_ form: FormInfo, answers: [String: JSONValue]) -> [String: String] {
        let active = activeAnswers(form, answers: answers)
        var errors: [String: String] = [:]
        for field in form.fields where isActive(field, answers: active) {
            let f = field.fields
            if field.isFallback { errors[f.key] = "This field needs a newer client."; continue }
            if field.type == "external" {
                if active[f.key]?.boolValue != true { errors[f.key] = "Complete the external step and confirm below." }
                continue
            }
            guard let value = active[f.key] else {
                if f.required { errors[f.key] = "Required" }
                continue
            }
            if let error = validate(field, value: value) { errors[f.key] = error }
        }
        return errors
    }
    private static func validate(_ field: FormField, value: JSONValue) -> String? {
        let f = field.fields
        switch field {
        case .string:
            guard let text = value.stringValue else { return "Enter text." }
            if f.required && text.isEmpty { return "Required" }
            if let min = f.minLength, Double(text.utf16.count) < min { return "Enter at least \(min.formatted()) characters." }
            if let max = f.maxLength, Double(text.utf16.count) > max { return "Enter at most \(max.formatted()) characters." }
            if let pattern = f.pattern {
                guard let regex = try? NSRegularExpression(pattern: pattern), regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return "Match the requested format." }
            }
            if f["options"] != nil && !f.custom && !f.options.contains(where: { $0.value == text }) { return "Choose one of the options." }
            if f.format == "email" && text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { return "Enter an email address." }
            if f.format == "uri", URL(string: text)?.scheme == nil { return "Enter a full URL." }
            if f.format == "date", !validDate(text) { return "Enter a date as YYYY-MM-DD." }
            if f.format == "date-time", !validTimestamp(text) { return "Enter a date and time with a time zone." }
        case .number, .integer:
            guard let number = value.doubleValue, number.isFinite else { return "Enter a number." }
            if field.type == "integer" && number.rounded() != number { return "Enter a whole number." }
            if let min = f.minimum, number < min { return "Minimum: \(min.formatted())" }
            if let max = f.maximum, number > max { return "Maximum: \(max.formatted())" }
        case .boolean:
            if value.boolValue == nil { return "Choose Yes or No." }
        case .multiselect:
            guard let items = value.arrayValue, items.allSatisfy({ $0.stringValue != nil }) else { return "Choose answers." }
            if f.required && items.isEmpty { return "Required" }
            if Set(items).count != items.count { return "Choose each answer once." }
            if let min = f.minItems, Double(items.count) < min { return "Choose at least \(min.formatted()) answers." }
            if let max = f.maxItems, Double(items.count) > max { return "Choose at most \(max.formatted()) answers." }
            if !f.custom && items.contains(where: { value in !f.options.contains { .string($0.value) == value } }) { return "Choose from the listed options." }
        default: break
        }
        return nil
    }
    private static func validDate(_ text: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: text).map { formatter.string(from: $0) == text } ?? false
    }
    private static func validTimestamp(_ text: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text) != nil
    }
}
