import Foundation
import Testing
@testable import OCRender

@Test func fileSearchFindsEveryOccurrenceAndPreservesUTF16Ranges() async {
    let result = await CodeSearchResult.find("name", in: "😀 name NAME\n\tname\r\nnomatch")
    #expect(result.matches == [.init(line: 1, range: .init(location: 3, length: 4)), .init(line: 1, range: .init(location: 8, length: 4)), .init(line: 2, range: .init(location: 1, length: 4))])
    #expect(result.lines[1]?.count == 2)
    #expect(await CodeSearchResult.find("", in: "name").matches.isEmpty)
    #expect(await CodeSearchResult.find("missing", in: "name").matches.isEmpty)
}

@Test func diffFormatsHeadersAndRanges() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/source/review")
    for file in ["jsdiff.patch", "git.patch"] {
        let document = DiffParser.parse(try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8))
        #expect(document.kind == .text)
        #expect(document.hunks.count == 1)
        #expect(document.lines.filter { $0.kind == .deletion }.count == 1)
        #expect(!document.lines.contains { $0.text.hasPrefix("---") || $0.text.hasPrefix("+++") })
        #expect(document.oldText.contains("value = 1"))
        #expect(document.newText.contains("value = 2"))
    }
}
@Test func diffMalformedAndSpecialCasesNeverTrap() {
    #expect(DiffParser.parse("").kind == .empty)
    #expect(DiffParser.parse("Binary files a and b differ\n").kind == .binary)
    #expect(DiffParser.parse("--- a\n+++ b\n").kind == .headerOnly)
    for patch in ["arbitrary", "@@ nope\n+x", "@@ -1,1 +1,1 @@\n+x", "@@ -999999999999999999999999,1 +1 @@\n+x", "@@ -1 +1 @@\n-a\n+b\n+c"] {
        #expect(DiffParser.parse(patch).kind == .raw)
    }
    let doc = DiffParser.parse("--- a\n+++ b\n@@ -1 +1 @@\n-\told\r\n+\tnew\r\n\\ No newline at end of file\n")
    #expect(doc.lines[0].text == "\told\r")
    #expect(doc.lines[0].displayText == "  old␍")
    #expect(doc.lines.last?.kind == .noNewline)
}
@Test func contextExpandsTwentyInEitherDirectionAndSplitPairsInOrder() async {
    let patch = "--- a\n+++ b\n@@ -1,105 +1,106 @@\n" + (1...52).map { " line \($0)\n" }.joined() + "-old\n+new\n+extra\n" + (54...105).map { " line \($0)\n" }.joined()
    let doc = await DiffParser.prepare(patch)
    let rows = DiffRows.make(doc, split: true)
    #expect(rows.filter { $0.hidden != nil }.count == 2)
    #expect(rows.contains { $0.left?.text == "old" && $0.right?.text == "new" })
    #expect(rows.contains { $0.left == nil && $0.right?.text == "extra" })
    var expansion = DiffExpansion()
    if let range = rows.first?.hidden {
        expansion.expand(range, fromEnd: true)
        #expect(expansion.revealed.count == 20)
        #expect(DiffRows.make(doc, expansion: expansion).first?.hidden?.count == range.count - 20)
    }
    #expect(DiffRows.make(doc, showAll: true).count == 107)
    var bounded = doc; bounded.fullFile = false
    #expect(!DiffRows.make(bounded).contains { $0.expandable })
}
@Test func wordTokenizationCapsAndHighlightMapping() async {
    #expect(WordDiff.tokens("foo  bar(x)").map(\.text) == ["foo", "  ", "bar", "(", "x", ")"])
    let result = WordDiff.changed("let value = 1", "let value = 2")
    #expect(result.0 == [NSRange(location: 12, length: 1)])
    #expect(result.1 == [NSRange(location: 12, length: 1)])
    #expect(WordDiff.changed(String(repeating: "a", count: 1001), "b").0.isEmpty)
    let doc = await DiffParser.prepare("--- a\n+++ b\n@@ -1 +1 @@\n-let value = 1\n+let value = 2\n")
    let highlighted = await DiffHighlighter.shared.highlight(doc, path: "test.swift", hash: "test-word-map")
    #expect(!highlighted.lines[0].syntax.isEmpty && !highlighted.lines[1].syntax.isEmpty)
    #expect(highlighted.lines[0].syntax.allSatisfy { NSMaxRange($0.range) <= highlighted.lines[0].text.utf16.count })
    #expect(FileLanguage.language(for: "file.svg") == "html")
    #expect(FileLanguage.language(for: "unknown.ext") == nil)
    let stringSource = "let title = \"Original\""
    let strings = await CodeHighlighter.shared.highlight(stringSource, language: "swift")
    #expect(strings.contains { $0.kind == .string && Range($0.range, in: stringSource).map { stringSource[$0] == "\"Original\"" } == true })
}
@Test func fiveThousandPairedChangesPreparation() async throws {
    func ms(_ duration: Duration) -> Double { Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15 }
    // The parallel suite competes for the host's cores, so the budget applies to the best of three cold runs.
    // Each run changes a different number, so no highlighter or document cache can answer it.
    var runs: [Double] = []
    for run in 1...3 {
        let patch = "--- a/Large.swift\n+++ b/Large.swift\n@@ -1,5000 +1,5000 @@\n" + (1...5000).map { "-let value\($0) = \($0)\n" }.joined() + (1...5000).map { "+let value\($0) = \($0 + run)\n" }.joined()
        let start = ContinuousClock.now
        let document = await DiffParser.prepare(patch)
        let parsed = ContinuousClock.now
        let highlighted = await DiffHighlighter.shared.highlight(document, path: "Large.swift", hash: MarkdownBlock.hash(patch))
        let styled = ContinuousClock.now
        let unified = await DiffRows.prepare(highlighted), split = await DiffRows.prepare(highlighted, split: true)
        runs.append(ms(start.duration(to: .now)))
        #expect(unified.count == 10_000 && split.count == 5_000)
        #expect(highlighted.lines.allSatisfy { !$0.words.isEmpty && !$0.syntax.isEmpty })
        print("Diff preparation run \(run) phases parse-word \(start.duration(to: parsed)) highlight \(parsed.duration(to: styled)) rows \(styled.duration(to: .now))")
    }
    let best = runs.min() ?? .infinity
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent(".build/performance")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try JSONEncoder().encode(["preparationMilliseconds": best, "preparationSlowestRunMilliseconds": runs.max() ?? best]).write(to: output.appendingPathComponent("diff-preparation-host.json"))
    #expect(best < 500, "Diff preparation took \(runs) ms")
}

@Test func crlfHeadersAndMissingNewlineReconstructBothSides() {
    let document = DiffParser.parse("--- a\r\n+++ b\r\n@@ -1 +1 @@\r\n-old\r\n\\ No newline at end of file\n+new\r\n\\ No newline at end of file\n")
    #expect(document.kind == .text)
    #expect(document.oldText == "old\r" && document.newText == "new\r")
    #expect(document.headers.count == 2 && document.lines.filter { $0.kind == .noNewline }.count == 2)
}

@Test func openingADeletedLineUsesItsCurrentFileAnchor() {
    let document = DiffParser.parse("@@ -42,2 +12,1 @@\n context\n-deleted\n", fullFile: false)
    #expect(document.firstChangedLine == 13)
    let onlyDeletion = DiffParser.parse("@@ -1 +0,0 @@\n-deleted\n", fullFile: false)
    #expect(onlyDeletion.firstChangedLine == 1)
}
@Test func diffPreviewSizesFromRenderedRowsNotPatchLines() {
    let body = "@@ -1,3 +1,3 @@\n a\n-b\n+c\n d\n"
    let patch = "Index: main.swift\n===================================================================\n--- main.swift\n+++ main.swift\n" + body
    // File headers are not rows, so they add no height.
    #expect(DiffPreview.estimatedRows(patch) == DiffPreview.estimatedRows(body))
    #expect(DiffPreview.estimatedRows(patch) < patch.components(separatedBy: "\n").count)
    #expect(DiffPreview.estimatedRows("") == 1)
    #expect(DiffPreview.lineHeight(font: 13) == 24)
    #expect(DiffPreview.lineHeight(font: 22) == 37)
    // A measurement replaces the estimate; content past the cap is clipped and flagged.
    let estimated = DiffPreview.height(measured: nil, rows: 4, font: 22)
    #expect(estimated.height == 4 * 37 && !estimated.clipped)
    let measured = DiffPreview.height(measured: 300, rows: 4, font: 22)
    #expect(measured.height == 300 && !measured.clipped)
    let capped = DiffPreview.height(measured: 10_000, rows: 4, font: 13)
    #expect(capped.height == Double(DiffPreview.maxRows) * 24 && capped.clipped)
}
