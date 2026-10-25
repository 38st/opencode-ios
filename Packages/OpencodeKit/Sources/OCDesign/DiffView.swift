#if os(iOS)
import SwiftUI
import UIKit
import CoreText
import OCRender
import OCModels

public struct OCDiffInput: Equatable, Sendable, Identifiable {
    public let id: String
    public let path: String
    public let text: String
    public let source: Bool
    public let fullFile: Bool
    public let expanded: Bool
    public let summary: String
    public let imageData: Data?
    public let mediaMessage: String?
    public init(path: String, text: String, source: Bool = false, fullFile: Bool = true, expanded: Bool = true, summary: String = "", imageData: Data? = nil, mediaMessage: String? = nil) {
        self.imageData = imageData; self.mediaMessage = mediaMessage
        id = path; self.path = path; self.text = text; self.source = source; self.fullFile = fullFile; self.expanded = expanded; self.summary = summary
    }
}

public struct OCDiffSelection: Identifiable {
    public let id = UUID()
    public let file: String
    public let selection: LineSelection
    public let preview: String
    public let deletedText: String
}

public struct OCDiffView: View {
    let inputs: [OCDiffInput]
    let split: Bool
    let showAll: Bool
    let wrap: Bool
    let headers: Bool
    let comments: [LineComment]
    let selected: LineSelection?
    let selectedFile: String?
    let search: CodeSearchResult
    let currentMatch: CodeSearchMatch?
    let onMove: ((Int) -> Void)?
    let onComment: (OCDiffSelection) -> Void
    let onToggle: (String) -> Void
    let onOpen: (String) -> Void
    let onEdit: (LineComment) -> Void
    let onDelete: (LineComment) -> Void
    let refresh: (() -> Void)?
    let scrolls: Bool
    let onContentHeight: ((CGFloat) -> Void)?
    let inlineComment: LineComment?
    let inlineEditor: AnyView?
    @Binding var scrollOffset: Double
    @State private var documents: [String: DiffDocument] = [:]
    @State private var sections: [CodeSection] = []
    @State private var expansion: [String: DiffExpansion] = [:]
    @State private var generation = 0
    @State private var preparedKey = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ inputs: [OCDiffInput], split: Bool = false, showAll: Bool = false, wrap: Bool = true, headers: Bool = false,
                comments: [LineComment] = [], selected: LineSelection? = nil, selectedFile: String? = nil, search: CodeSearchResult = .init(), currentMatch: CodeSearchMatch? = nil, scrollOffset: Binding<Double> = .constant(0),
                onComment: @escaping (OCDiffSelection) -> Void = { _ in }, onToggle: @escaping (String) -> Void = { _ in },
                onOpen: @escaping (String) -> Void = { _ in }, onEdit: @escaping (LineComment) -> Void = { _ in },
                onDelete: @escaping (LineComment) -> Void = { _ in }, inlineComment: LineComment? = nil, inlineEditor: AnyView? = nil, onMove: ((Int) -> Void)? = nil, refresh: (() -> Void)? = nil,
                scrolls: Bool = true, onContentHeight: ((CGFloat) -> Void)? = nil) {
        self.inputs = inputs; self.split = split; self.showAll = showAll; self.wrap = wrap; self.headers = headers
        self.inlineComment = inlineComment; self.inlineEditor = inlineEditor
        self.comments = comments; self.selected = selected; self.selectedFile = selectedFile; _scrollOffset = scrollOffset; self.onComment = onComment
        self.search = search; self.currentMatch = currentMatch
        self.onMove = onMove
        self.onToggle = onToggle; self.onOpen = onOpen; self.onEdit = onEdit; self.onDelete = onDelete; self.refresh = refresh
        self.scrolls = scrolls; self.onContentHeight = onContentHeight
    }
    public var body: some View {
        GeometryReader { geometry in
            let split = split && geometry.size.width >= 560 && !typeSize.isAccessibilitySize
            let wrap = wrap || typeSize.isAccessibilitySize
            let measurementKey = inputs.filter(\.expanded).map { $0.id + MarkdownBlock.hash($0.text) }.joined() + "\(split)\(wrap)"
            CodeCollection(sections: sections, measurementKey: measurementKey, ready: preparedKey == measurementKey, split: split, wrap: wrap, headers: headers, selected: selected, selectedFile: selectedFile,
                           search: search, currentMatch: currentMatch,
                           fontSize: fontSize, scrollOffset: $scrollOffset, onComment: makeComment,
                           onToggle: onToggle, onOpen: onOpen, onEdit: onEdit, onDelete: onDelete,
                           inlineEditor: inlineEditor, onMove: onMove, onExpand: { path, range, end, all in
                               expansion[path, default: .init()].expand(range, fromEnd: end, all: all)
                           }, refresh: refresh, scrolls: scrolls)
                .task(id: PreparationKey(inputs: inputs, split: split, all: showAll, expansion: expansion, comments: comments + (inlineComment.map { [$0] } ?? []), width: geometry.size.width, wrap: wrap, font: fontSize)) {
                    generation += 1; let revision = generation
                    #if DEBUG
                    DiffPreparation.inFlight += 1; defer { DiffPreparation.inFlight -= 1; DiffPreparation.finished += 1 }
                    #endif
                    var plain: [String: DiffDocument] = [:]
                    for input in inputs where input.expanded {
                        if input.source {
                            plain[input.id] = await Self.sourceDocument(input.text)
                        } else { plain[input.id] = await DiffParser.prepare(input.text, fullFile: input.fullFile) }
                    }
                    guard !Task.isCancelled else { return }
                    documents = plain
                    sections = await prepareSections(plain, split: split, width: geometry.size.width, wrap: wrap)
                    preparedKey = measurementKey
                    reportHeight()
                    for input in inputs where input.expanded {
                        guard let doc = plain[input.id] else { continue }
                        plain[input.id] = await DiffHighlighter.shared.highlight(doc, path: input.path, hash: MarkdownBlock.hash(input.text))
                    }
                    guard !Task.isCancelled, generation == revision else { return }
                    documents = plain
                    sections = await prepareSections(plain, split: split, width: geometry.size.width, wrap: wrap)
                    reportHeight()
                }
        }
    }
    private var fontSize: CGFloat { Self.fontSize(typeSize) }
    static func fontSize(_ typeSize: DynamicTypeSize) -> CGFloat { typeSize.isAccessibilitySize ? 22 : typeSize >= .xxxLarge ? 19 : typeSize >= .xLarge ? 16 : 13 }
    /// The content height CodeLayout lays out: every measured row plus the section headers.
    private func reportHeight() {
        guard let onContentHeight else { return }
        onContentHeight(sections.reduce(0) { $0 + $1.heights.reduce(0, +) + (headers ? ($1.expanded ? 88 : 44) : 0) })
    }
    private func prepareSections(_ docs: [String: DiffDocument], split: Bool, width: CGFloat, wrap: Bool) async -> [CodeSection] {
        var result: [CodeSection] = []
        for input in inputs {
            let doc = docs[input.id]
            var rows = await doc.mapAsync { await DiffRows.prepare($0, split: split, showAll: showAll || input.source, expansion: expansion[input.id] ?? .init()) } ?? []
            if let doc, rows.isEmpty && input.expanded {
                rows = [.init(id: 0, label: doc.kind == .headerOnly ? "Diff too large to render" : doc.kind == .empty || doc.kind == .binary ? "Binary file" : "No changes")]
            }
            if input.expanded {
                if input.imageData != nil { rows = [.init(id: -2, label: "Image", commentID: "__image")] }
                else if let message = input.mediaMessage { rows = [.init(id: -2, label: message)] }
            }
            let annotations = comments.filter { $0.file == input.path && $0.id != inlineComment?.id }
            if !annotations.isEmpty || inlineComment?.file == input.path {
                var annotated: [DiffRow] = []
                for row in rows {
                    annotated.append(row)
                    for (i, comment) in annotations.enumerated() {
                        let line = comment.selection?.deleted == true ? row.left?.oldLine : (row.right ?? row.left)?.newLine
                        if line != nil && line == (comment.selection?.deleted == true ? comment.selection?.upper : comment.selection?.newRange.upperBound) {
                            var annotation = DiffRow(id: -1_000_000 - i, label: (comment.selection?.label ?? "Comment") + "\n" + comment.comment, commentID: comment.id)
                            annotation.commentOnOldSide = comment.selection?.deleted == true
                            annotated.append(annotation)
                        }
                    }
                    if let editor = inlineComment, editor.file == input.path, let selection = editor.selection {
                        let line = selection.deleted ? row.left?.oldLine : (row.right ?? row.left)?.newLine
                        if line == (selection.deleted ? selection.upper : selection.newRange.upperBound) {
                            var placement = DiffRow(id: Int.min, label: "", commentID: "__editor")
                            placement.commentOnOldSide = selection.deleted
                            annotated.append(placement)
                        }
                    }
                }
                rows = annotated
            }
            let largest = doc?.lines.reduce(1) { max($0, $1.oldLine ?? 0, $1.newLine ?? 0) } ?? 1
            let digits = max(3, String(largest).count)
            let gutter = CGFloat(split || input.source ? digits : digits * 2 + 1) * fontSize * 0.61 + 24
            let heights = await CodeMetrics.heights(rows, width: width, split: split, wrap: wrap, font: fontSize, gutter: gutter)
            // Monospaced text: the widest line bounds horizontal scrolling when wrapping is off.
            let widest = rows.reduce(0) { max($0, $1.left?.displayText.utf16.count ?? 0, $1.right?.displayText.utf16.count ?? 0) }
            result.append(.init(id: input.id, title: input.path, summary: input.summary, rows: rows, heights: heights, comments: annotations, imageData: input.imageData, expanded: input.expanded, gutter: gutter, source: input.source,
                                textWidth: CGFloat(widest) * fontSize * 0.61 + 24))
        }
        return result
    }
    private func makeComment(_ file: String, _ input: LineSelection) {
        var selection = input
        guard let doc = documents[file] else { return }
        if selection.side != selection.endSide, let rows = sections.first(where: { $0.id == file })?.rows {
            func number(_ row: DiffRow, side: LineSelection.Side) -> Int? { side == .deletions ? row.left?.oldLine : (row.right ?? row.left)?.newLine }
            if let a = rows.firstIndex(where: { number($0, side: selection.side) == selection.start }),
               let b = rows.firstIndex(where: { number($0, side: selection.endSide) == selection.end }) {
                let numbers = rows[min(a, b)...max(a, b)].compactMap { number($0, side: .additions) }
                selection.newStart = numbers.min(); selection.newEnd = numbers.max()
            }
        }
        let lines = doc.lines.filter { line in
            let number = selection.deleted ? line.oldLine : line.newLine
            return number.map { (selection.deleted ? selection.lower...selection.upper : selection.newRange).contains($0) } ?? false
        }.map(\.text)
        onComment(.init(file: file, selection: selection, preview: lines.prefix(2).joined(separator: "\n"), deletedText: selection.deleted ? lines.prefix(20).joined(separator: "\n") : ""))
    }
    @concurrent private static func sourceDocument(_ text: String) async -> DiffDocument {
        .init(lines: text.components(separatedBy: "\n").enumerated().map { .init(kind: .context, text: $0.element, newLine: $0.offset + 1) })
    }
    private struct PreparationKey: Equatable {
        let inputs: [OCDiffInput]; let split: Bool; let all: Bool; let expansion: [String: DiffExpansion]
        let comments: [LineComment]; let width: CGFloat; let wrap: Bool; let font: CGFloat
    }
}
private extension Optional where Wrapped == DiffDocument {
    func mapAsync<T>(_ transform: (Wrapped) async -> T) async -> T? { if let value = self { return await transform(value) }; return nil }
}

struct CodeSection {
    let revision = UUID()
    let id: String
    let title: String
    let summary: String
    let rows: [DiffRow]
    let heights: [CGFloat]
    let comments: [LineComment]
    let imageData: Data?
    let expanded: Bool
    let gutter: CGFloat
    let source: Bool
    /// The width of the widest line, measured off the main actor.
    let textWidth: CGFloat
}

nonisolated enum CodeMetrics {
    private actor Cache {
        static let shared = Cache()
        private var values: [Int: [CGFloat]] = [:]
        private var order: [Int] = []
        private var bytes = 0
        func get(_ key: Int) -> [CGFloat]? { values[key] }
        func put(_ heights: [CGFloat], key: Int) {
            guard values[key] == nil else { return }
            let cost = heights.count * MemoryLayout<CGFloat>.stride + 64
            guard cost <= 8 * 1_048_576 else { return }
            while bytes + cost > 8 * 1_048_576, let first = order.first {
                bytes -= (values.removeValue(forKey: first)?.count ?? 0) * MemoryLayout<CGFloat>.stride + 64
                order.removeFirst()
            }
            values[key] = heights; order.append(key); bytes += cost
        }
    }
    @concurrent static func heights(_ rows: [DiffRow], width: CGFloat, split: Bool, wrap: Bool, font: CGFloat, gutter: CGFloat) async -> [CGFloat] {
        var hash = Hasher()
        hash.combine(width); hash.combine(split); hash.combine(wrap); hash.combine(font); hash.combine(gutter)
        for row in rows {
            hash.combine(row.left?.text); hash.combine(row.right?.text); hash.combine(row.label); hash.combine(row.commentID)
        }
        let key = hash.finalize()
        if let cached = await Cache.shared.get(key) { return cached }
        let columnWidth = max(1, (split ? width / 2 : width) - gutter)
        let lineHeight = CGFloat(DiffPreview.lineHeight(font: Double(font)))
        let ctFont = CTFontCreateWithName("JetBrainsMonoNFM-Regular" as CFString, font, nil)
        let heights = rows.map { row -> CGFloat in
            if let label = row.label {
                if row.commentID == "__image" { return 280 }
                if row.commentID == "__editor" { return font >= 22 ? 420 : font >= 19 ? 280 : 220 }
                guard row.commentID != nil else { return lineHeight }
                let cardWidth = min(400, (split ? width / 2 : width) - 24) - 68
                let count = label.components(separatedBy: "\n").reduce(0) { $0 + max(1, Int(ceil(CGFloat($1.utf16.count) * font * 0.61 / max(1, cardWidth)))) }
                return max(88, CGFloat(count) * lineHeight + 40)
            }
            guard wrap else { return lineHeight }
            func height(_ line: DiffLine?) -> CGFloat {
                guard let line else { return lineHeight }
                let display = line.displayText
                if CGFloat(display.utf16.count) * font * 0.61 <= columnWidth { return lineHeight }
                let attributed = NSAttributedString(string: display, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont])
                let typesetter = CTTypesetterCreateWithAttributedString(attributed)
                var index = 0, lines = 0
                while index < attributed.length {
                    let count = CTTypesetterSuggestClusterBreak(typesetter, index, columnWidth)
                    index += max(1, count); lines += 1
                }
                return CGFloat(max(1, lines)) * lineHeight
            }
            return max(height(row.left), height(row.right))
        }
        await Cache.shared.put(heights, key: key)
        return heights
    }
}
#endif

#if DEBUG
/// Snapshot tests wait for every diff to finish preparing, including the highlighted second pass.
@MainActor public enum DiffPreparation {
    public static var inFlight = 0, finished = 0
    /// Waits briefly for a preparation to start, then until none is running.
    public static func settle() async {
        let start = finished
        var waited = 0
        while inFlight == 0, finished == start, waited < 200 { try? await Task.sleep(for: .milliseconds(10)); waited += 1 }
        waited = 0
        while inFlight > 0, waited < 1_500 { try? await Task.sleep(for: .milliseconds(10)); waited += 1 }
    }
}
#endif
