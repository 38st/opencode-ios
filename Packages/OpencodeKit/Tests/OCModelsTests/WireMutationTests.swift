import Foundation
import Testing
import OCFoundation
@testable import OCModels

/// Check the decoded representation, including nested unions, after each mutation.
func checkMutations<T: Codable>(_ raw: JSONValue, as type: T.Type,
                               validate: (T) throws -> Void = { _ in }) throws {
    let original = try raw.decoded(type)
    try validate(original)
    let baseline = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(original))
    for numbers in [false, true] {
        let input = mutateWire(raw, numbers: numbers)
        let decoded = try input.decoded(type)
        try validate(decoded)
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(decoded))
        #expect(stripMutation(encoded) == stripMutation(mutateWire(baseline, numbers: numbers)))
    }
    // Null and missing must be equivalent, including inside nested objects.
    let nulls = nullOptionalFields(raw)
    let withNull = try nulls.decoded(type), withoutNull = try nulls.omittingNullFields.decoded(type)
    try validate(withNull)
    #expect(try JSONEncoder().encode(withNull).decodedJSON == JSONEncoder().encode(withoutNull).decodedJSON)
}
private extension Data {
    var decodedJSON: JSONValue { get throws { try JSONDecoder().decode(JSONValue.self, from: self) } }
}
func mutateWire(_ raw: JSONValue, numbers: Bool = false) -> JSONValue {
    switch raw {
    case .object(let fields):
        var result = fields.mapValues { mutateWire($0, numbers: numbers) }
        result["_futureField"] = .bool(true); result["_futureNull"] = .null
        if result["metadata"] == nil { result["metadata"] = .null }
        return .object(result)
    case .array(let values): return .array(values.map { mutateWire($0, numbers: numbers) })
    case .integer, .double: return numbers ? .string("NaN") : raw
    default: return raw
    }
}
func stripMutation(_ raw: JSONValue) -> JSONValue {
    switch raw {
    case .object(let fields): return .object(fields.filter { !$0.key.hasPrefix("_future") && !$0.value.isNull }.mapValues(stripMutation))
    case .array(let values): return .array(values.map(stripMutation))
    default: return raw
    }
}
private func nullOptionalFields(_ raw: JSONValue) -> JSONValue {
    switch raw {
    case .object(let fields):
        var result = fields.mapValues(nullOptionalFields)
        for key in ["metadata", "description", "parentID", "revert", "retry", "error", "cost", "tokens", "completed"] {
            if result[key] != nil { result[key] = .null }
        }
        return .object(result)
    case .array(let values): return .array(values.map(nullOptionalFields))
    default: return raw
    }
}
func validateMessage(_ row: SessionMessage) {
    #expect(!row.isFallback)
    for content in row.content {
        #expect(!content.isFallback)
        if content.type == "tool" {
            #expect(!content.fields.toolState.isFallback)
            #expect(content.fields.toolState.fields.content.allSatisfy { !$0.isFallback })
        }
    }
}
func validateInbox(_ item: InboxItem) {
    #expect(!item.isFallback)
    if case .unknown = item.delivery { Issue.record("Unknown delivery") }
}
func validateForm(_ form: FormInfo) {
    #expect(form.fields.allSatisfy { !$0.isFallback })
    #expect(form.state?.isFallback != true)
}

@Test func everyReadUnionRetainsUnknownAndMalformedElements() throws {
    func check<T: Codable>(_ type: T.Type, discriminator: String = "type", valid: JSONValue,
                          raw: (T) -> JSONValue, fallback: (T) -> Bool) throws {
        var future = valid; future.set(discriminator, .string("future"))
        let values = try JSONValue.array([valid, future, .integer(42), valid]).decoded([T].self)
        #expect(values.count == 4)
        #expect(!fallback(values[0]) && fallback(values[1]) && fallback(values[2]) && !fallback(values[3]))
        #expect(raw(values[1]) == future && raw(values[2]) == .integer(42))
        #expect(raw(values[0]) == raw(values[3]))
    }
    try check(SessionMessage.self, valid: .object(["type": .string("user"), "id": .string("m")]), raw: \.raw, fallback: \.isFallback)
    try check(AssistantContent.self, valid: .object(["type": .string("text"), "text": .string("ok")]), raw: \.raw, fallback: \.isFallback)
    try check(ToolState.self, discriminator: "status", valid: .object(["status": .string("running")]), raw: \.raw, fallback: \.isFallback)
    try check(ToolContent.self, valid: .object(["type": .string("text"), "text": .string("ok")]), raw: \.raw, fallback: \.isFallback)
    try check(InboxItem.self, valid: .object(["type": .string("user")]), raw: \.raw, fallback: \.isFallback)
    try check(FormField.self, valid: .object(["type": .string("string")]), raw: \.raw, fallback: \.isFallback)
    try check(FormState.self, discriminator: "status", valid: .object(["status": .string("pending")]), raw: \.raw, fallback: \.isFallback)
    try check(MCPStatus.self, discriminator: "status", valid: .object(["status": .string("connected")]), raw: \.raw, fallback: \.isFallback)
}
