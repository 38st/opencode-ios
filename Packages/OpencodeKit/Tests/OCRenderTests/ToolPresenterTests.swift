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
@Test func onlyFileToolsCarryAnOpenablePath() {
    let registry = ToolPresenterRegistry()
    func presentation(_ name: String, _ input: JSONValue, output: String? = nil) -> ToolPresentation {
        var raw = tool(name, input: input)
        if let output { raw.set(["state", "content"], .array([.object(["type": .string("text"), "text": .string(output)])])) }
        return registry.presentation(.init(raw: raw))
    }
    #expect(presentation("read", .object(["path": .string("Sources/main.swift")])).path == "Sources/main.swift")
    #expect(presentation("edit", .object(["path": .string("main.swift")])).path == "main.swift")
    #expect(presentation("write", .object(["path": .string("new.swift"), "content": .string("x")])).path == "new.swift")
    // A directory read lists entries, and search summaries are not paths.
    #expect(presentation("read", .object(["path": .string("Sources")]), output: "Read directory Sources\nmain.swift").path == nil)
    let glob = presentation("glob", .object(["pattern": .string("*.txt")]))
    #expect(glob.path == nil && !glob.subtitle.isEmpty)
    #expect(presentation("grep", .object(["pattern": .string("original")])).path == nil)
}
