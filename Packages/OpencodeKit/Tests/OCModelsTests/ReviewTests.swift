import Foundation
import Testing
import OCFoundation
@testable import OCModels

// Expected URI strings are the reference request.test.ts:169–217 cases.
@Test func referenceRequestFileURIs() {
    let cases: [(String, String, LineSelection?, String)] = [
        ("D:\\projects\\myapp", "src\\foo.ts", nil, "file:///D:/projects/myapp/src/foo.ts"),
        ("C:\\Users\\test\\Documents", "file#name.txt", nil, "file:///C:/Users/test/Documents/file%23name.txt"),
        ("/home/user/project", "src/app.ts", nil, "file:///home/user/project/src/app.ts"),
        ("C:\\current\\project", "D:\\other\\project\\file.ts", nil, "file:///D:/other/project/file.ts"),
        ("C:\\project", "src\\App.tsx", .init(start: 10, end: 20), "file:///C:/project/src/App.tsx?start=10&end=20"),
        ("C:\\projects\\myapp\\src", "..\\..\\shared\\util.ts", nil, "file:///C:/projects/myapp/src/../../shared/util.ts"),
        ("D:\\workspace\\app", "src\\utils\\helper.ts", nil, "file:///D:/workspace/app/src/utils/helper.ts"),
    ]
    for (directory, path, selection, expected) in cases {
        var text = AttributedString("@" + path)
        text[MentionAttribute.self] = .init(kind: "file", value: path, selection: selection)
        let input = ComposerInput.encode(text, directory: directory, agent: nil, model: nil)
        #expect(input.files?.map(\.uri) == [expected])
    }
}
@Test func referenceCommentFilesAreNotDeduplicatedButMentionsAre() {
    var text = AttributedString("@src/foo.ts")
    text[MentionAttribute.self] = .init(kind: "file", value: "src/foo.ts")
    let comments: [LineComment] = [.init(file: "src/foo.ts", comment: "focus here"), .init(file: "src/review.ts", comment: "Compare with @src/shared.ts and @src/review.ts.")]
    let input = ComposerInput.encode(text, directory: "/repo", comments: comments, agent: nil, model: nil)
    #expect(input.files?.map(\.uri) == ["file:///repo/src/foo.ts", "file:///repo/src/foo.ts", "file:///repo/src/review.ts", "file:///repo/src/shared.ts"])
    #expect(input.text == "@src/foo.ts\nThe user made the following comment regarding this file of src/foo.ts: focus here\nThe user made the following comment regarding this file of src/review.ts: Compare with @src/shared.ts and @src/review.ts.")
}
@Test func malformedCountsCannotOverflowTotals() {
    let file = FileDiff(raw: .object(["additions": .integer(Int64.max), "deletions": .integer(Int64.max), "status": .string("future")]))
    #expect(file.changedLines == Int.max)
    #expect(FileDiff.totals([file, file]).additions == Int.max)
    #expect(file.statusKind == .unknown("future"))
}

@Test func reviewPathMapsProjectRepositoryAndLocationWithoutParents() {
    #expect(ReviewPath("packages/a.swift", root: .project, location: "/work/packages", project: "/work") == ReviewPath("a.swift", root: .location, location: "/work/packages", project: "/work"))
    let outside = ReviewPath("README.md", root: .repository, location: "/work/packages", project: "/work")
    #expect(outside?.directory == "/work" && outside?.path == "README.md")
    #expect(ReviewPath("../README.md", root: .location, location: "/work/packages", project: "/work") == outside)
    #expect(ReviewPath("../../secret", root: .location, location: "/work/packages", project: "/work") == nil)
    #expect(ReviewPath("src/a.ts", root: .project, location: "/trees/feature/src", project: "/trees/feature")?.absolute == "/trees/feature/src/a.ts")
    #expect(ReviewPath("x\0", root: .location, location: "/work", project: "/work") == nil)
}
@Test func reviewSourcesTolerateStartupAndUnknownStatus() throws {
    let empty = try JSONDecoder().decode(VCSInfo.self, from: Data(#"{"provider":null,"branch":null,"future":true}"#.utf8))
    #expect(ReviewSource.available(vcs: empty, session: true).isEmpty)
    let vcs = VCSInfo(raw: .object(["provider": .string("git"), "branch": .object(["current": .string("feature"), "default": .string("main")])]))
    #expect(ReviewSource.available(vcs: vcs, session: true) == [.working, .branch, .lastTurn])
    let diff = try JSONDecoder().decode(FileDiff.self, from: Data(#"{"file":"a","status":"future","additions":null,"deletions":"NaN"}"#.utf8))
    #expect(diff.additions == 0 && diff.deletions == 0 && diff.status == "future")
}
@Test func commentsMatchReferenceWireOrderingAndStrings() throws {
    var text = AttributedString("Check @file.ts")
    let lower = text.characters.index(text.startIndex, offsetBy: 6)
    text[lower..<text.endIndex][MentionAttribute.self] = .init(kind: "file", value: "file.ts")
    let comments = [LineComment(file: "src/a.ts", selection: .init(start: 14, end: 12), comment: "  Use @other.ts, then @other.ts!  ", origin: "review", preview: "const a = 1"), LineComment(file: "src/a.ts", selection: .init(start: 12, end: 14), comment: "Again")]
    let input = ComposerInput.encode(text, directory: "/workspace", files: [.init(uri: "data:text/plain;base64,eA==")], comments: comments, agent: nil, model: nil)
    #expect(input.text == "Check @file.ts\nThe user made the following comment regarding lines 12 through 14 of src/a.ts: Use @other.ts, then @other.ts!\nThe user made the following comment regarding lines 12 through 14 of src/a.ts: Again")
    #expect(input.files?.map(\.uri) == ["file:///workspace/file.ts", "file:///workspace/src/a.ts?start=12&end=14", "file:///workspace/other.ts", "file:///workspace/src/a.ts?start=12&end=14", "data:text/plain;base64,eA=="])
    #expect(input.metadata?["displayText"] == .string("Check @file.ts"))
    #expect(input.metadata?["comments"]?[0]?["selection"]?["startChar"] == .integer(0))
    let restored = LineComment.restore(try JSONDecoder().decode(JSONValue.self, from: input.body(id: "msg_test")))
    #expect(restored.count == 2 && restored[0].selection?.lower == 12 && restored[0].preview == "const a = 1")
    #expect(!restored[0].id.isEmpty && restored[0].id != restored[1].id)
}
@Test func deletedCommentsNeverAttachUnrelatedCurrentLines() {
    let comment = LineComment(file: "a.swift", selection: .init(start: 2, end: 3, side: .deletions), comment: "Keep this", deletedText: "old one\nold two")
    let input = ComposerInput.encode(AttributedString(), directory: "/p", comments: [comment], agent: nil, model: nil)
    #expect(input.files?.isEmpty == true)
    #expect(input.text == "The user made the following comment regarding deleted lines 2 through 3 of a.swift: Keep this\n```\nold one\nold two\n```")
    #expect(input.metadata?["comments"]?[0]?["side"] == .string("deletions"))
    let mixed = LineComment(file: "a", selection: .init(start: 20, end: 3, side: .deletions, endSide: .additions), comment: "Mixed")
    #expect(ComposerInput.encode(AttributedString(), directory: "/p", comments: [mixed], agent: nil, model: nil).files?.first?.uri == "file:///p/a?start=3&end=3")
    #expect(LineComment.parseNote("The user made the following comment regarding this file of a.ts: Context")?.file == "a.ts")
}
@Test func fileContentAndLinks() {
    #expect(FileContent(data: Data([65, 0])).binary)
    #expect(!FileContent(data: Data(repeating: 65, count: 8192) + Data([0])).binary)
    #expect(FileContent(data: Data("a\npartial".utf8), total: 100).text == "a\n")
    for link in ["a.ts:12", "a.ts:12:2", "a.ts#L12", "file:///p/a.ts?start=12&end=12"] { #expect(FileLink(link).selection?.lower == 12) }
    #expect(FileLink("a.ts:12-14").selection?.upper == 14)
    #expect(FileLink("a.ts#L12-L14").selection?.upper == 14)
    #expect(FileLink("file:///p/space%20name.ts:12").path == "/p/space name.ts")
}

@Test func windowsAndUNCLinksUseTheSameRootMapping() {
    let path = ReviewPath("sub\\a.swift", root: .project, location: "C:\\repo\\sub", project: "C:\\repo")
    #expect(path?.directory == "C:/repo/sub" && path?.path == "a.swift")
    #expect(FileLink("file:///C:/repo/a%20b.swift?start=12&end=14").path == "C:/repo/a b.swift")
    #expect(FileLink("file://server/share/a.swift#L3-L5").path == "//server/share/a.swift")
    #expect(ReviewPath("..\\README.md", root: .location, location: "C:/repo/sub", project: "C:/repo")?.path == "README.md")
    #expect(ReviewPath("..\\..\\secret", root: .location, location: "C:/repo/sub", project: "C:/repo") == nil)
}

@Test func fileLinksMatchReferenceResolveLinkCases() {
    let cases: [(String, String, Int?, Int?)] = [
        ("packages/app/src/app.tsx", "packages/app/src/app.tsx", nil, nil),
        ("session/timeline/interaction.ts:74", "session/timeline/interaction.ts", 74, 74),
        ("packages/app/src/workspaces/files/model.tsx:164:11", "packages/app/src/workspaces/files/model.tsx", 164, 164),
        ("src/components/markdown.tsx:398-410", "src/components/markdown.tsx", 398, 410),
        ("src/components/markdown.tsx#L398", "src/components/markdown.tsx", 398, 398),
        ("src/components/markdown.tsx#L398-L410", "src/components/markdown.tsx", 398, 410),
        ("file:///C:/repo/a/b.ts?x=1#L3", "C:/repo/a/b.ts", 3, 3),
        ("what?.md", "what?.md", nil, nil), ("a#b.md#L10", "a#b.md", 10, 10),
        ("foo.ts:0", "foo.ts", nil, nil), ("./a/../b.ts", "b.ts", nil, nil),
        ("..", "..", nil, nil), ("C:12", "C:12", nil, nil),
        ("../timeline/interaction.ts:74", "../timeline/interaction.ts", 74, 74),
        ("src/C#/a.cs", "src/C#/a.cs", nil, nil), ("foo#bar.ts", "foo#bar.ts", nil, nil),
        ("foo.ts:12:", "foo.ts", 12, 12), ("foo.ts:99999999999999999999", "foo.ts", nil, nil),
        (#"\\server\share\x.ts"#, "//server/share/x.ts", nil, nil),
        ("file://server/share/x%20y.ts", "//server/share/x y.ts", nil, nil),
        ("a%2520b.ts", "a%2520b.ts", nil, nil), ("C:/foo/../../x.ts", "C:/x.ts", nil, nil),
        ("file:///C:/tmp/demo%20file.ts:12", "C:/tmp/demo file.ts", 12, 12),
    ]
    for (href, path, start, end) in cases {
        let link = FileLink(href)
        #expect(link.path == path, "\(href)")
        #expect(link.selection?.start == start && link.selection?.end == end, "\(href)")
    }
}

@Test func promptCommentPresentationSkipsMalformedEntriesAndRestoresDeletedSide() {
    let deleted = LineComment(file: "old.swift", selection: .init(start: 4, side: .deletions), comment: "Keep the check", deletedText: "guard ready else { return }")
    let entries: [JSONValue] = [
        .null, .object(["path": .integer(4), "comment": .string("Bad path")]),
        .object(["path": .string("a"), "comment": .string("Bad selection"), "selection": .object(["startLine": .integer(2)])]),
        .object(["path": .string("a"), "comment": .string("Bad preview"), "preview": .integer(5)]),
        .object(["path": .string("a"), "comment": .string("Bad origin"), "origin": .string("future")]),
        .object(["path": .string("a"), "comment": .string("Whole file"), "selection": .null]), deleted.metadata,
    ]
    let restored = LineComment.restore(.object(["metadata": .object(["displayText": .string(""), "comments": .array(entries)])]))
    #expect(restored.count == 2)
    #expect(restored.first?.selection == nil)
    #expect(restored.last?.selection?.deleted == true && restored.last?.deletedText == deleted.deletedText)
    #expect(restored.last?.note == deleted.note)
}
