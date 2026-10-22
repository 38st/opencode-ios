import Foundation
import Testing
import OCFoundation
import OCModels

@Test func externalCompletionCannotBeDefaultedOrHiddenByUnknownProperties() throws {
    let f = try form(#"[{"key":"external","type":"external","url":"https://example.com","default":true,"hidden":true,"when":[{"key":"missing","op":"eq","value":true}]}]"#)
    #expect(FormValidation.visibleFields(f, answers: [:]).count == 1)
    #expect(FormValidation.activeAnswers(f, answers: [:]).isEmpty)
    #expect(FormValidation.errors(f, answers: [:])["external"] != nil)
    #expect(FormValidation.errors(f, answers: ["external": .bool(true)]).isEmpty)
}

private func form(_ fields: String) throws -> FormInfo {
    try JSONDecoder().decode(FormInfo.self, from: Data((#"{"id":"frm","sessionID":"s","title":"Questions","fields": "# + fields + "}").utf8))
}
@Test func conditionalFieldsCascadeAndMissingDoesNotSatisfyNotEqual() throws {
    let f = try form(#"[{"type":"multiselect","key":"a","options":[{"value":"x","label":"X"}]},{"type":"boolean","key":"b","required":true,"when":[{"key":"a","op":"eq","value":"x"}]},{"type":"string","key":"c","required":true,"when":[{"key":"b","op":"neq","value":false}]}]"#)
    #expect(FormValidation.errors(f, answers: [:]).isEmpty)
    #expect(FormValidation.errors(f, answers: ["a": .array([.string("x")])])["b"] == "Required")
    #expect(FormValidation.errors(f, answers: ["a": .array([.string("x")]), "b": .bool(true)])["c"] == "Required")
    #expect(FormValidation.activeAnswers(f, answers: ["a": .array([]), "b": .bool(true), "c": .string("stale")]) == ["a": .array([])])
}
@Test func everyFieldValidatesConstraintsAndExternalRequiresExplicitAcknowledgement() throws {
    let f = try form(#"[{"type":"string","key":"s","required":true,"options":[{"value":"one","label":"One"}],"custom":true,"minLength":2},{"type":"multiselect","key":"m","options":[{"value":"x","label":"X"},{"value":"y","label":"Y"}],"minItems":1,"maxItems":1,"required":true},{"type":"number","key":"n","minimum":1,"maximum":3},{"type":"integer","key":"i"},{"type":"boolean","key":"b","required":true},{"type":"external","key":"e","url":"https://example.com"}]"#)
    let invalid: [String: JSONValue] = ["s": .string("a"), "m": .array([.string("x"), .string("y")]), "n": .integer(4), "i": .double(1.5), "b": .string("yes")]
    #expect(Set(FormValidation.errors(f, answers: invalid).keys) == ["s", "m", "n", "i", "b", "e"])
    let good: [String: JSONValue] = ["s": .string("Other text"), "m": .array([.string("x")]), "n": .double(2.5), "i": .integer(2), "b": .bool(false), "e": .bool(true)]
    #expect(FormValidation.errors(f, answers: good).isEmpty)
    #expect(FormValidation.activeAnswers(f, answers: good)["e"] == .bool(true))
}
@Test func hiddenDefaultsAndUnsupportedFieldsDoNotAutoSubmit() throws {
    let f = try form(#"[{"type":"string","key":"token","hidden":true,"default":"provided"},{"type":"future","key":"future","required":true}]"#)
    #expect(FormValidation.activeAnswers(f, answers: [:]) == ["token": .string("provided")])
    #expect(FormValidation.visibleFields(f, answers: [:]).count == 1)
    #expect(FormValidation.errors(f, answers: [:])["future"] != nil)
}
