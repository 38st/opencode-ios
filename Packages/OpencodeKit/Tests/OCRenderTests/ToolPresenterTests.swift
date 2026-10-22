import Foundation
import Testing
import OCModels
import OCFoundation
import OCRender

@Test func toolMappingAndUnknownFallback() {
    let registry = ToolPresenterRegistry()
    let styles: [(String, ToolPresentation.Style)] = [("read", .explore), ("glob", .explore), ("grep", .explore), ("edit", .diff), ("apply_patch", .diff), ("patch", .diff), ("write", .addedFile), ("bash", .shell), ("shell", .shell), ("task", .subagent), ("subagent", .subagent), ("question", .question), ("skill", .compact), ("webfetch", .compact), ("websearch", .links), ("execute", .execute), ("todowrite", .compact)]
    for (name, style) in styles { #expect(registry.presentation(.init(raw: tool(name))).style == style) }
    var unknown = tool("future_tool", input: .object(["foo": .string("bar")]))
    unknown.set(["state", "content"], .array([.object(["type": .string("text"), "text": .string("result")])]))
    let result = registry.presentation(.init(raw: unknown))
    #expect(result.title == "future_tool"); #expect(result.badge == "MCP")
    #expect(result.input.contains("bar")); #expect(result.output == "result")
}
@Test func completedShellReportsExitAndTimeoutAndCodeModeNestedFailure() {
    let registry = ToolPresenterRegistry()
    let shell = registry.presentation(.init(raw: tool("shell", metadata: .object(["exit": .integer(3), "shellID": .string("sh")]))))
    #expect(shell.badge == "Exit 3"); #expect(shell.failed); #expect(shell.shellID == "sh")
    let timeout = registry.presentation(.init(raw: tool("shell", metadata: .object(["timeout": .bool(true)]))))
    #expect(timeout.badge == "Timed out"); #expect(timeout.failed)
    let execute = registry.presentation(.init(raw: tool("execute", metadata: .object(["toolCalls": .array([.object(["name": .string("read"), "status": .string("error")])])]))))
    #expect(execute.nested.count == 1); #expect(execute.failed)
}
