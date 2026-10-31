#if os(iOS)
import UIKit
import SwiftUI
import OCRender
import OCModels

struct CodeCollection: UIViewControllerRepresentable {
    let sections: [CodeSection]
    let measurementKey: String
    let ready: Bool
    let split: Bool
    let wrap: Bool
    let headers: Bool
    let selected: LineSelection?
    let selectedFile: String?
    let search: CodeSearchResult
    let currentMatch: CodeSearchMatch?
    let fontSize: CGFloat
    @Binding var scrollOffset: Double
    let onComment: (String, LineSelection) -> Void
    let onToggle: (String) -> Void
    let onOpen: (String) -> Void
    let onEdit: (LineComment) -> Void
    let onDelete: (LineComment) -> Void
    let inlineEditor: AnyView?
    let onMove: ((Int) -> Void)?
    let onExpand: (String, Range<Int>, Bool, Bool) -> Void
    let refresh: (() -> Void)?
    /// Inline previews size themselves to their content and leave vertical scrolling to the page.
    let scrolls: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> CodeCollectionController {
        OCFonts.register()
        let layout = CodeLayout()
        let view = CodeCollectionView(frame: .zero, collectionViewLayout: layout)
        // Code and diffs read left to right in every language.
        view.semanticContentAttribute = .forceLeftToRight
        view.backgroundColor = UIColor(OCColor.backgroundDeep)
        view.register(CodeImageCell.self, forCellWithReuseIdentifier: "image")
        view.register(CodeEditorCell.self, forCellWithReuseIdentifier: "editor")
        view.register(CodeCell.self, forCellWithReuseIdentifier: "code")
        view.register(CodeHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        view.dataSource = context.coordinator; view.delegate = context.coordinator
        view.accessibilityIdentifier = "diffCollection"
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectLines(_:)))
        longPress.minimumPressDuration = 0.4; longPress.delegate = context.coordinator; view.addGestureRecognizer(longPress)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.horizontal(_:)))
        pan.delegate = context.coordinator; view.addGestureRecognizer(pan)
        view.addGestureRecognizer(UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hover(_:))))
        context.coordinator.view = view
        view.viewportChanged = { [weak coordinator = context.coordinator] in coordinator?.revealEditor() }
        #if DEBUG
        context.coordinator.recorder = DiffFrameRecorder(view: view)
        #endif
        let controller = CodeCollectionController(collection: view)
        return controller
    }
    static func dismantleUIViewController(_ controller: CodeCollectionController, coordinator: Coordinator) {
        coordinator.stopDecay()
        #if DEBUG
        coordinator.recorder?.stop()
        #endif
    }
    func updateUIViewController(_ controller: CodeCollectionController, context: Context) {
        let view = controller.collection
        let coordinator = context.coordinator
        #if DEBUG
        coordinator.recorder?.begin(measurementKey)
        #endif
        coordinator.parent = self
        if let code = view as? CodeCollectionView { code.move = onMove }
        view.isScrollEnabled = scrolls
        if (refresh != nil) != (view.refreshControl != nil) {
            if refresh != nil {
                let control = UIRefreshControl(); control.addTarget(coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged); view.refreshControl = control
            } else { view.refreshControl = nil }
        }
        guard let layout = view.collectionViewLayout as? CodeLayout else { return }
        let signature = sections.map { $0.revision.uuidString }.joined() + "\(split)\(wrap)\(fontSize)"
        if coordinator.signature != signature || layout.width != view.bounds.width {
            coordinator.signature = signature
            #if DEBUG
            if let recorder = coordinator.recorder {
                recorder.split = split; recorder.wrap = wrap
                recorder.rows = 0; recorder.highlightedLines = 0; recorder.wordDiffLines = 0
                for section in sections { for row in section.rows {
                    recorder.rows += 1
                    for line in [row.left, row.right].compactMap({ $0 }) {
                        if !line.syntax.isEmpty { recorder.highlightedLines += 1 }
                        if !line.words.isEmpty { recorder.wordDiffLines += 1 }
                    }
                } }
            }
            #endif
            layout.expanded = sections.map(\.expanded); layout.heights = sections.map(\.heights); layout.headers = headers; layout.invalidateLayout()
            coordinator.horizontalOffset = min(coordinator.horizontalOffset, coordinator.maxHorizontalOffset())
            view.reloadData()
            if sections.count == 1, coordinator.documentID != sections.first?.id {
                coordinator.documentID = sections.first?.id; coordinator.restored = false
            }
            if let file = coordinator.requestedFile, let index = sections.firstIndex(where: { $0.id == file && $0.expanded && !$0.rows.isEmpty }) {
                view.layoutIfNeeded(); view.setContentOffset(CGPoint(x: 0, y: layout.origin(for: index)), animated: false); coordinator.requestedFile = nil
            }
            if !coordinator.restored, ready, !sections.isEmpty { view.layoutIfNeeded(); view.contentOffset.y = scrollOffset; coordinator.restored = true }
        } else {
            for path in view.indexPathsForVisibleItems { if let cell = view.cellForItem(at: path) as? CodeCell { coordinator.configure(cell, at: path) } }
        }
        if coordinator.lastSelected != selected || coordinator.lastSelectedFile != selectedFile || coordinator.lastSelectedDocumentID != sections.first?.id, let selected {
            if let section = selectedFile.flatMap({ id in sections.firstIndex { $0.id == id } }) ?? sections.indices.first, let row = sections[section].rows.firstIndex(where: { (selected.deleted ? $0.left?.oldLine : ($0.right ?? $0.left)?.newLine) == selected.lower }) {
                coordinator.lastSelected = selected; coordinator.lastSelectedFile = selectedFile; coordinator.lastSelectedDocumentID = sections.first?.id
                view.layoutIfNeeded(); view.scrollToItem(at: IndexPath(item: max(0, row - 4), section: section), at: .top, animated: false)
            }
        }
        if headers, ready, selected == nil, coordinator.lastSelectedFile != selectedFile,
           let section = sections.firstIndex(where: { $0.id == selectedFile && $0.expanded }) {
            if coordinator.lastSelectedFile != nil || scrollOffset == 0 {
                view.layoutIfNeeded()
                view.setContentOffset(CGPoint(x: 0, y: layout.origin(for: section)), animated: false)
            }
            coordinator.lastSelectedFile = selectedFile
        }
        coordinator.revealEditor()
    }
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {
        #if DEBUG
        var recorder: DiffFrameRecorder?
        #endif
        var parent: CodeCollection
        weak var view: UICollectionView?
        var signature = "", restored = false
        var documentID: String?
        var requestedFile: String?
        var lastSelected: LineSelection?
        var lastSelectedFile: String?
        var lastSelectedDocumentID: String?
        var start: (String, Int, LineSelection.Side)?
        var selection: LineSelection?
        /// A pointer is over the code. Its secondary click opens a line's menu; a touch long press keeps selecting lines.
        var hovering = false
        @objc func hover(_ recognizer: UIHoverGestureRecognizer) { hovering = recognizer.state == .began || recognizer.state == .changed }
        var horizontalOffset: CGFloat = 0
        private var decay: CADisplayLink?
        private var velocity: CGFloat = 0, lastTick: CFTimeInterval = 0
        var editorPath: IndexPath?
        var editorViewportHeight: CGFloat = 0
        init(_ parent: CodeCollection) { self.parent = parent }
        func revealEditor() {
            guard parent.inlineEditor != nil, let view else { editorPath = nil; return }
            for (section, value) in parent.sections.enumerated() {
                guard let row = value.rows.firstIndex(where: { $0.commentID == "__editor" }) else { continue }
                let path = IndexPath(item: row, section: section)
                guard editorPath != path || editorViewportHeight != view.bounds.height,
                      let frame = view.collectionViewLayout.layoutAttributesForItem(at: path)?.frame else { return }
                editorPath = path; editorViewportHeight = view.bounds.height
                let height = min(frame.height, max(1, view.bounds.height - view.adjustedContentInset.top - view.adjustedContentInset.bottom))
                view.scrollRectToVisible(CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), animated: false)
                return
            }
        }
        func numberOfSections(in collectionView: UICollectionView) -> Int { parent.sections.count }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { parent.sections.indices.contains(section) ? parent.sections[section].rows.count : 0 }
        func collectionView(_ view: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            if parent.sections[indexPath.section].rows[indexPath.item].commentID == "__image" {
                let cell = view.dequeueReusableCell(withReuseIdentifier: "image", for: indexPath)
                if let image = cell as? CodeImageCell { image.configure(parent.sections[indexPath.section].imageData) }
                return cell
            }
            if parent.sections[indexPath.section].rows[indexPath.item].commentID == "__editor" {
                let cell = view.dequeueReusableCell(withReuseIdentifier: "editor", for: indexPath)
                if let editor = cell as? CodeEditorCell, let content = parent.inlineEditor {
                    editor.configure(content, split: parent.split, oldSide: parent.sections[indexPath.section].rows[indexPath.item].commentOnOldSide)
                }
                return cell
            }
            let cell = view.dequeueReusableCell(withReuseIdentifier: "code", for: indexPath)
            if let cell = cell as? CodeCell { configure(cell, at: indexPath) }; return cell
        }
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            #if DEBUG
            if parent.ready { recorder?.rowsReady() }
            #endif
        }
        func configure(_ cell: CodeCell, at path: IndexPath) {
            guard parent.sections.indices.contains(path.section), parent.sections[path.section].rows.indices.contains(path.item) else { return }
            let section = parent.sections[path.section], row = section.rows[path.item]
            cell.configure(row, split: parent.split, wrap: parent.wrap, fontSize: parent.fontSize, offset: horizontalOffset,
                           selected: start?.0 == section.id ? selection : parent.selectedFile == nil || parent.selectedFile == section.id ? parent.selected : nil, comments: section.comments, gutter: section.gutter, source: section.source,
                           matches: parent.search.lines[(row.right ?? row.left)?.newLine ?? 0] ?? [], currentMatch: parent.currentMatch)
            if let comment = section.comments.first(where: { $0.id == row.commentID }) {
                cell.commentActions(edit: { self.parent.onEdit(comment) }, delete: { self.parent.onDelete(comment) })
            } else if let range = row.hidden {
                cell.contextActions(above: { self.parent.onExpand(section.id, range, false, false) }, below: { self.parent.onExpand(section.id, range, true, false) }, all: { self.parent.onExpand(section.id, range, false, true) })
            } else if DiffPlaceholder.opensFile(row.label) {
                cell.fileAction { self.parent.onOpen(section.id) }
            }
            cell.comment = { [weak self] side in
                guard let self, let line = side == .deletions ? row.left?.oldLine : (row.right ?? row.left)?.newLine else { return }
                self.parent.onComment(section.id, .init(start: line, side: side))
            }
            cell.extend = { [weak self] side in
                guard let self, let line = side == .deletions ? row.left?.oldLine : (row.right ?? row.left)?.newLine else { return }
                let prior = self.parent.selected ?? .init(start: line, side: side)
                self.selection = .init(start: prior.start, end: line, side: prior.side, endSide: side)
                self.parent.onComment(section.id, self.selection ?? prior)
            }
        }
        func collectionView(_ view: UICollectionView, viewForSupplementaryElementOfKind kind: String, at path: IndexPath) -> UICollectionReusableView {
            let header = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: path)
            if let header = header as? CodeHeader {
                let section = parent.sections[path.section]
                header.configure(title: section.title, summary: section.summary, expanded: section.expanded, toggle: { self.requestedFile = section.expanded ? nil : section.id; self.parent.onToggle(section.id) }, open: { self.parent.onOpen(section.id) })
            }; return header
        }
        func collectionView(_ view: UICollectionView, didSelectItemAt path: IndexPath) {
            _ = view.next?.becomeFirstResponder()
            let section = parent.sections[path.section], row = section.rows[path.item]
            if let range = row.hidden { parent.onExpand(section.id, range, false, false) }
            else if DiffPlaceholder.opensFile(row.label) { parent.onOpen(section.id) }
        }
        func collectionView(_ view: UICollectionView, contextMenuConfigurationForItemAt path: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
            let section = parent.sections[path.section], row = section.rows[path.item]
            if hovering, row.commentID == nil, row.hidden == nil, let menu = lineMenu(section, row: row, right: parent.split && point.x >= view.bounds.width / 2) { return menu }
            guard row.commentID != "__editor", row.hidden != nil || row.commentID != nil else { return nil }
            return UIContextMenuConfiguration(actionProvider: { _ in
                var actions: [UIMenuElement] = []
                if let range = row.hidden {
                    actions += [UIAction(title: localized("Expand 20 lines above")) { _ in self.parent.onExpand(section.id, range, false, false) },
                                UIAction(title: localized("Expand 20 lines below")) { _ in self.parent.onExpand(section.id, range, true, false) },
                                UIAction(title: localized("Expand all", comment: "Reveals every hidden unchanged line in a diff")) { _ in self.parent.onExpand(section.id, range, false, true) }]
                }
                for comment in section.comments where comment.id == row.commentID || comment.selection?.upper == (row.right ?? row.left)?.newLine {
                    actions += [UIAction(title: localized("Edit", comment: "Menu action that edits a line comment")) { _ in self.parent.onEdit(comment) }, UIAction(title: localized("Delete", comment: "Menu action that deletes a line comment"), attributes: .destructive) { _ in self.parent.onDelete(comment) }]
                }
                actions.append(UIAction(title: localized("Copy line")) { _ in OCCopy.text((row.right ?? row.left)?.text ?? row.label ?? "") })
                return UIMenu(title: localized("More options"), children: actions)
            })
        }
        private func lineMenu(_ section: CodeSection, row: DiffRow, right: Bool) -> UIContextMenuConfiguration? {
            guard let line = parent.split ? (right ? row.right : row.left) ?? row.right ?? row.left : row.right ?? row.left else { return nil }
            let side: LineSelection.Side = parent.split ? (right ? .additions : .deletions) : line.kind == .deletion ? .deletions : .additions
            let number = side == .deletions ? line.oldLine ?? line.newLine : line.newLine ?? line.oldLine
            return UIContextMenuConfiguration(actionProvider: { _ in
                var actions: [UIMenuElement] = []
                if let number { actions.append(UIAction(title: localized("Comment", comment: "Verb: menu action that comments on a diff line"), image: nil) { _ in self.parent.onComment(section.id, .init(start: number, side: side)) }) }
                actions.append(UIAction(title: localized("Copy line")) { _ in OCCopy.text(line.text) })
                if !section.source { actions.append(UIAction(title: localized("Open file")) { _ in self.parent.onOpen(section.id) }) }
                return UIMenu(children: actions)
            })
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            #if DEBUG
            recorder?.scrolling = true
            #endif
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            #if DEBUG
            recorder?.scrolling = false
            #endif
            parent.scrollOffset = scrollView.contentOffset.y
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { parent.scrollOffset = scrollView.contentOffset.y }
            #if DEBUG
            if !decelerate { recorder?.scrolling = false }
            #endif
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {}
        @objc func refresh(_ control: UIRefreshControl) { parent.refresh?(); control.endRefreshing() }
        func point(_ recognizer: UILongPressGestureRecognizer) -> (String, Int, LineSelection.Side)? {
            guard let view, let index = view.indexPathForItem(at: recognizer.location(in: view)) else { return nil }
            let section = parent.sections[index.section], row = section.rows[index.item]
            let right = parent.split && recognizer.location(in: view).x >= view.bounds.width / 2
            let cell = right ? row.right : row.left
            guard row.commentID == nil, let cell, let number = cell.newLine ?? cell.oldLine else { return nil }
            let side: LineSelection.Side = parent.split ? (right ? .additions : .deletions) : cell.kind == .deletion ? .deletions : .additions
            return (section.id, side == .deletions ? cell.oldLine ?? number : cell.newLine ?? number, side)
        }
        @objc func selectLines(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { start = point(recognizer) }
            if let start, let end = point(recognizer), start.0 == end.0 {
                selection = .init(start: start.1, end: end.1, side: start.2, endSide: end.2)
                if let view { for path in view.indexPathsForVisibleItems { if let cell = view.cellForItem(at: path) as? CodeCell { configure(cell, at: path) } } }
            }
            if recognizer.state == .ended, let start, let selection { parent.onComment(start.0, selection); self.start = nil }
            if recognizer.state == .cancelled { start = nil; selection = nil }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let press = gestureRecognizer as? UILongPressGestureRecognizer { return point(press) != nil }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view else { return true }
            let velocity = pan.velocity(in: view)
            return !parent.wrap && abs(velocity.x) > abs(velocity.y)
        }
        /// With wrapping off, every line scrolls together and stops at the widest visible line.
        func maxHorizontalOffset() -> CGFloat {
            guard let view, !parent.wrap else { return 0 }
            let column = parent.split ? view.bounds.width / 2 : view.bounds.width
            return parent.sections.filter { !parent.headers || $0.expanded }.reduce(0) { max($0, $1.textWidth - max(1, column - $1.gutter)) }
        }
        private func setHorizontal(_ value: CGFloat) {
            let clamped = min(max(0, value), maxHorizontalOffset())
            guard clamped != horizontalOffset, let view else { return }
            horizontalOffset = clamped
            for path in view.indexPathsForVisibleItems { if let cell = view.cellForItem(at: path) as? CodeCell { configure(cell, at: path) } }
        }
        @objc func horizontal(_ pan: UIPanGestureRecognizer) {
            guard let view else { return }
            if pan.state == .began { stopDecay() }
            setHorizontal(horizontalOffset - pan.translation(in: view).x); pan.setTranslation(.zero, in: view)
            if pan.state == .ended { startDecay(-pan.velocity(in: view).x) }
        }
        private func startDecay(_ initial: CGFloat) {
            stopDecay()
            guard abs(initial) > 20 else { return }
            velocity = initial; lastTick = 0
            let link = CADisplayLink(target: self, selector: #selector(decelerate(_:)))
            link.add(to: .main, forMode: .common); decay = link
        }
        func stopDecay() { decay?.invalidate(); decay = nil; velocity = 0 }
        @objc private func decelerate(_ link: CADisplayLink) {
            let elapsed = lastTick == 0 ? link.duration : link.timestamp - lastTick
            lastTick = link.timestamp
            let before = horizontalOffset
            setHorizontal(horizontalOffset + velocity * CGFloat(elapsed))
            // UIScrollView's normal rate: the velocity keeps 0.998 of itself per millisecond.
            velocity *= CGFloat(pow(Double(UIScrollView.DecelerationRate.normal.rawValue), elapsed * 1000))
            if abs(velocity) < 10 || horizontalOffset == before { stopDecay() }
        }
    }
}

final class CodeCollectionController: UIViewController {
    let collection: UICollectionView
    init(collection: UICollectionView) { self.collection = collection; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() { view = collection }
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? { (collection as? CodeCollectionView)?.keyCommands }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(handleCodeKey(_:)) { return (collection as? CodeCollectionView)?.move != nil }
        return super.canPerformAction(action, withSender: sender)
    }
    @objc private func handleCodeKey(_ command: UIKeyCommand) { (collection as? CodeCollectionView)?.handleCodeKey(command) }
}

private final class CodeCollectionView: UICollectionView {
    var viewportChanged: (() -> Void)?
    var move: ((Int) -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(handleCodeKey(_:)) || action == #selector(previousFile) || action == #selector(nextFile) { return move != nil }
        return super.canPerformAction(action, withSender: sender)
    }
    override var keyCommands: [UIKeyCommand]? {
        let commands = move == nil ? [] : [WorkspaceKeys.CodeList.previous, WorkspaceKeys.CodeList.next].map { $0.keyCommand(#selector(handleCodeKey(_:))) }
        return commands + (super.keyCommands ?? [])
    }
    @objc fileprivate func handleCodeKey(_ command: UIKeyCommand) {
        if WorkspaceKeys.CodeList.previous.matches(command) { move?(-1) }
        else if WorkspaceKeys.CodeList.next.matches(command) { move?(1) }
    }
    @objc private func previousFile() { move?(-1) }
    @objc private func nextFile() { move?(1) }
    private var viewport = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if viewport != bounds.size { viewport = bounds.size; viewportChanged?() }
    }
}

final class CodeLayout: UICollectionViewLayout {
    var heights: [[CGFloat]] = [] { didSet { dirty = true } }
    var expanded: [Bool] = [] { didSet { dirty = true } }
    var headers = false, width: CGFloat = 0
    private var dirty = true
    private var frames: [[CGRect]] = [], headerFrames: [CGRect] = [], total: CGFloat = 0
    override func prepare() {
        guard let collectionView else { return }
        guard dirty || width != collectionView.bounds.width else { return }; dirty = false; width = collectionView.bounds.width
        var y: CGFloat = 0; frames = []; headerFrames = []
        for (index, section) in heights.enumerated() {
            let headerHeight: CGFloat = headers ? (expanded.indices.contains(index) && expanded[index] ? 88 : 44) : 0
            headerFrames.append(CGRect(x: 0, y: y, width: width, height: headerHeight)); y += headerHeight
            frames.append(section.map { height in defer { y += height }; return CGRect(x: 0, y: y, width: width, height: height) })
        }; total = y
    }
    func origin(for section: Int) -> CGFloat { headerFrames.indices.contains(section) ? headerFrames[section].minY : 0 }
    override var collectionViewContentSize: CGSize { CGSize(width: width, height: total) }
    override func layoutAttributesForItem(at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(path.section), frames[path.section].indices.contains(path.item) else { return nil }
        let value = UICollectionViewLayoutAttributes(forCellWith: path); value.frame = frames[path.section][path.item]; return value
    }
    override func layoutAttributesForSupplementaryView(ofKind kind: String, at path: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard headers, headerFrames.indices.contains(path.section) else { return nil }
        let value = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: kind, with: path)
        var frame = headerFrames[path.section]
        let end = path.section + 1 < headerFrames.count ? headerFrames[path.section + 1].minY : total
        frame.origin.y = min(max(frame.minY, collectionView?.contentOffset.y ?? 0), end - frame.height)
        value.frame = frame; value.zIndex = 1; return value
    }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var result: [UICollectionViewLayoutAttributes] = []
        for (s, section) in frames.enumerated() {
            if headers, let h = layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: s)), h.frame.intersects(rect) { result.append(h) }
            var low = 0, high = section.count
            while low < high { let middle = (low + high) / 2; if section[middle].maxY < rect.minY { low = middle + 1 } else { high = middle } }
            var i = low
            while i < section.count && section[i].minY <= rect.maxY {
                if let item = layoutAttributesForItem(at: IndexPath(item: i, section: s)) { result.append(item) }; i += 1
            }
        }; return result
    }
    override func shouldInvalidateLayout(forBoundsChange bounds: CGRect) -> Bool { headers || bounds.width != width }
}
#endif
