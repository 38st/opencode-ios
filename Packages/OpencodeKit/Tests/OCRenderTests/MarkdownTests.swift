import Foundation
import Testing
@testable import OCRender

@Test func markdownRetainsServerFileLinksWithoutEnablingOtherSchemes() {
    let block = MarkdownBlock(source: "[relative](Sources/Example.swift:2-3) [short](Example.swift:2) [file](file:///workspace/Example.swift#L2) [absolute](/workspace/Example.swift) [bad](javascript:alert) ![image](file:///private/image.png)")
    let links = block.attributed.runs.compactMap(\.link).map(\.absoluteString)
    #expect(links == ["Sources/Example.swift:2-3", "Example.swift:2", "file:///workspace/Example.swift#L2", "/workspace/Example.swift"])
    #expect(block.attributed.runs.allSatisfy { $0.imageURL == nil })
}

@Test func cleanupProtectsCodeAndHidesLeakedThinking() {
    let source = "Visible<think>secret\nthought</think> answer\n```xml\n<think>literal</think>\n```\n`<think>inline</think>`\n    <think>indented</think>"
    #expect(ModelOutputCleanup.clean(source) == "Visible\n answer\n```xml\n<think>literal</think>\n```\n`<think>inline</think>`\n    <think>indented</think>")
    #expect(ModelOutputCleanup.clean("Shown<think>still thinking") == "Shown")
}
@Test func markdownFreezesBlocksClosesFencesAndBlocksImages() async throws {
    let pipeline = StreamingMarkdown()
    let first = try await pipeline.update("# Heading\n\nParagraph\n\n```swift\nlet x = 1")
    #expect(first.count == 3)
    #expect(first.last?.closed == false)
    #expect(first.last?.code?.contains("let x = 1") == true)
    let second = try await pipeline.update("# Heading\n\nParagraph\n\n```swift\nlet x = 12\n```", complete: true)
    #expect(first[0] == second[0]); #expect(first[1] == second[1])
    #expect(first.last?.id == second.last?.id, "The streaming tail retains its view identity as its source changes")
    #expect(second.last?.closed == true)
    let third = try await pipeline.update("# Corrected\n\n![private](https://example.com/tracker.png) [bad](javascript:alert) [safe](https://example.com)", complete: true)
    #expect(third.first?.source.contains("Corrected") == true)
    for block in third { for run in block.attributed.runs { #expect(run.imageURL == nil); #expect(run.link?.scheme != "javascript") } }
}
@Test func duplicateBlocksHaveDistinctIDsAndParseRateIsBounded() async throws {
    let pipeline = StreamingMarkdown(), start = ContinuousClock.now
    for index in 0..<5 { _ = try await pipeline.update("Same\n\nSame\n\n\(index)") }
    let elapsed = start.duration(to: .now)
    #expect(elapsed >= .milliseconds(333))
    let result = try await pipeline.update("Same\n\nSame", complete: true)
    #expect(Set(result.map(\.id)).count == result.count)
}
@Test(arguments: ["swift", "typescript", "tsx", "javascript", "python", "json", "bash", "go", "rust", "markdown", "yaml", "html", "css"])
func grammarsHighlight(language: String) async {
    let samples = ["swift": "let name = \"hello\"", "typescript": "const x: string = 'hello'", "tsx": "const x = <div>Hi</div>", "javascript": "const x = 'hello'", "python": "x = 'hello' # comment", "json": "{\"x\": 1}", "bash": "echo \"hello\"", "go": "package main\nvar x = 1", "rust": "let x = 1;", "markdown": "# Heading", "yaml": "x: 42", "html": "<div class=\"a\">Hi</div>", "css": "div { color: red; }"]
    let source = samples[language] ?? ""
    let spans = await CodeHighlighter.shared.highlight(source, language: language)
    #expect(!spans.isEmpty, "\(language)")
    for span in spans { #expect(Range(span.range, in: source) != nil) }
}

@Test func nestedFencesAndMultilineInlineCodeKeepLiteralTags() {
    for source in ["> ```swift\n> <think>literal</think>\n> ```\nAnswer", "- ```xml\n  <think>literal</think>\n  ```\nAnswer", "`a\n<think>literal</think>\nb`"] {
        #expect(ModelOutputCleanup.clean(source) == source)
    }
    for source in [">     <think>literal</think>", "> >     <think>literal</think>", "> \t<think>literal</think>"] {
        #expect(ModelOutputCleanup.clean(source) == source)
    }
}

@Test func concurrentUpdatesStillRespectTheParseRate() async throws {
    let pipeline = StreamingMarkdown(), start = ContinuousClock.now
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<6 { group.addTask { _ = try await pipeline.update("Update \(index)") } }
        try await group.waitForAll()
    }
    #expect(await pipeline.parseCount == 6)
    #expect(start.duration(to: .now) >= .milliseconds(416))
}
