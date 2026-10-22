#if os(iOS)
import SwiftUI
import UIKit
import Observation
import OCModels
import OCSync
import OCDesign
import OCRender

/// ARCHITECTURE §3.1's fallback for the reproducible iOS 26.5 lazy-stack layout loop.
/// Cells retain observable content items; text deltas never reload the data source.
struct TimelineCollection: UIViewRepresentable {
    let rows: [TimelineRow]
    let store: ReadStore
    let session: SessionModel
    let transcript: TranscriptModel
    let detail: TimelineDetail
    let working: Bool
    let control: TimelineScrollControl
    let openChild: (String) -> Void
    let openRoot: (String) -> Void
    let atBottom: (Bool) -> Void
    let reachedTop: () -> Void
    var scheme: ColorScheme = .light
    var typeSize: DynamicTypeSize = .large
    var phase: ScenePhase = .active

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TimelineCollectionView {
        makeCollection(coordinator: context.coordinator)
    }
    func makeCollection(coordinator: Coordinator) -> TimelineCollectionView {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = OCSpacing.md
            let inset = max(OCSpacing.lg, (environment.container.effectiveContentSize.width - OCLayout.readable) / 2)
            section.contentInsets = .init(top: OCSpacing.lg, leading: inset, bottom: OCSpacing.lg, trailing: inset)
            return section
        }
        let view = TimelineCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = UIColor(OCColor.background)
        view.accessibilityIdentifier = "transcriptScroll"
        view.alwaysBounceVertical = true
        view.contentInsetAdjustmentBehavior = .never
        view.selfSizingInvalidation = .enabledIncludingConstraints
        view.register(TimelineCell.self, forCellWithReuseIdentifier: "row")
        coordinator.attach(view)
        return view
    }
    func updateUIView(_ view: TimelineCollectionView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ view: TimelineCollectionView, coordinator: Coordinator) {
        coordinator.parent.control.cancel()
        for cell in view.visibleCells { (cell as? TimelineCell)?.visibility.visible = false }
        view.delegate = nil; view.sizeChanged = nil
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: TimelineCollection
        weak var view: TimelineCollectionView?
        var source: UICollectionViewDiffableDataSource<Int, TimelineItemID>?
        var values: [String: TimelineRow] = [:]
        var ids: [TimelineItemID] = []
        var applying = false
        private var revision = 0
        init(_ parent: TimelineCollection) { self.parent = parent }
        func attach(_ view: TimelineCollectionView) {
            self.view = view; view.delegate = self
            parent.control.coordinator = self
            source = UICollectionViewDiffableDataSource(collectionView: view) { [weak self] view, path, id in
                guard let self, let cell = view.dequeueReusableCell(withReuseIdentifier: "row", for: path) as? TimelineCell else { return nil }
                cell.contentConfiguration = UIHostingConfiguration {
                    TimelineHostedRow(parent: self.parent, row: id.rowID.flatMap { self.values[$0] }, visibility: cell.visibility)
                        .id(id)
                }.margins(.all, 0)
                return cell
            }
            view.sizeChanged = { [weak self] in
                guard let self, !self.applying else { return }
                self.parent.control.followLatest()
            }
        }
        func update(_ next: TimelineCollection) {
            guard let view, let source else { return }
            let restyle = next.detail != parent.detail || next.scheme != parent.scheme || next.typeSize != parent.typeSize || next.phase != parent.phase
            parent = next
            let nextValues = Dictionary(next.rows.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            var seen: Set<String> = []
            let nextIDs = next.rows.compactMap { seen.insert($0.id).inserted ? TimelineItemID.row($0.id) : nil } + (next.working ? [.working] : [])
            let existing = Set(ids)
            let changed = nextIDs.filter { existing.contains($0) && (restyle || $0.rowID.flatMap { values[$0] } != $0.rowID.flatMap { nextValues[$0] }) }
            guard nextIDs != ids || !changed.isEmpty else { return }
            let anchor = visibleAnchor()
            values = nextValues; ids = nextIDs
            var snapshot = NSDiffableDataSourceSnapshot<Int, TimelineItemID>()
            snapshot.appendSections([0]); snapshot.appendItems(nextIDs)
            snapshot.reconfigureItems(changed)
            applying = true
            revision += 1
            let version = revision
            source.apply(snapshot, animatingDifferences: false) { [weak self, weak view] in
                guard let self, let view, self.revision == version else { return }
                view.layoutIfNeeded()
                if !self.parent.control.following, let anchor,
                   let index = self.ids.firstIndex(of: anchor.id),
                   let attributes = view.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) {
                    view.setContentOffset(CGPoint(x: 0, y: attributes.frame.minY - anchor.offset), animated: false)
                }
                self.applying = false
                if !self.performPending() { self.parent.control.followLatest() }
            }
        }
        private func visibleAnchor() -> (id: TimelineItemID, offset: CGFloat)? {
            guard let view, let path = view.indexPathsForVisibleItems.sorted().first,
                  let id = source?.itemIdentifier(for: path), let frame = view.layoutAttributesForItem(at: path)?.frame else { return nil }
            return (id, frame.minY - view.contentOffset.y)
        }
        func scrollLatest() {
            guard let view, !applying, !view.isDragging, !view.isDecelerating else { return }
            view.layoutIfNeeded()
            let y = max(-view.adjustedContentInset.top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
            if abs(view.contentOffset.y - y) > 0.5 { view.setContentOffset(CGPoint(x: 0, y: y), animated: false) }
        }
        @discardableResult func performPending() -> Bool {
            guard !applying, let id = parent.control.pendingID, let index = ids.firstIndex(of: .row(id)), let view else { return false }
            parent.control.pendingID = nil
            view.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: false)
            return true
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !applying, scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking else { return }
            let bottom = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height + scrollView.adjustedContentInset.bottom < 80
            parent.control.following = bottom
            parent.atBottom(bottom)
            if scrollView.contentOffset.y <= 40 { parent.reachedTop() }
        }
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            (cell as? TimelineCell)?.visibility.visible = true
        }
        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            (cell as? TimelineCell)?.visibility.visible = false
        }
    }
}

nonisolated enum TimelineItemID: Hashable, Sendable {
    case row(String), working
    var rowID: String? { if case .row(let id) = self { id } else { nil } }
}

@MainActor final class TimelineScrollControl {
    weak var coordinator: TimelineCollection.Coordinator?
    var following = true
    var pendingID: String?
    private var task: Task<Void, Never>?
    func followLatest() {
        guard following, task == nil else { return }
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.task = nil
                if self.following { self.coordinator?.scrollLatest() }
            } catch { self?.task = nil }
        }
    }
    func jumpToLatest() { following = true; pendingID = nil; coordinator?.scrollLatest(); followLatest() }
    func pauseFollowing() { following = false; pendingID = nil }
    func show(_ id: String) { following = false; pendingID = id; coordinator?.performPending() }
    func cancel() { task?.cancel(); task = nil }
    deinit { task?.cancel() }
}

final class TimelineCollectionView: UICollectionView {
    var sizeChanged: (() -> Void)?
    private var previousSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != contentSize { previousSize = contentSize; sizeChanged?() }
    }
}
@MainActor @Observable final class TimelineCellVisibility { var visible = false }
private final class TimelineCell: UICollectionViewCell {
    let visibility = TimelineCellVisibility()
    override func prepareForReuse() { super.prepareForReuse(); visibility.visible = false }
}
private struct TimelineHostedRow: View {
    let parent: TimelineCollection
    let row: TimelineRow?
    let visibility: TimelineCellVisibility
    var body: some View {
        Group {
            if let row {
                TimelineRowView(row: row, transcript: parent.transcript, store: parent.store, sessionID: parent.session.id,
                    directory: parent.session.info.location.directory, detail: parent.detail, openChild: parent.openChild, openRoot: parent.openRoot)
            } else {
                OCLabel("Working…", icon: "status-active").font(OCType.small).foregroundStyle(OCColor.textMuted)
                    .accessibilityIdentifier("sessionWorking")
            }
        }.environment(\.timelineCellVisible, visibility.visible)
            .environment(\.ocDisclosureInteraction) {
                parent.control.pauseFollowing()
                parent.atBottom(false)
            }
            .environment(\.dynamicTypeSize, parent.typeSize).environment(\.colorScheme, parent.scheme)
            .environment(\.scenePhase, parent.phase).ocTheme()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct TimelineVisibilityKey: EnvironmentKey { nonisolated static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    var timelineCellVisible: Bool? {
        get { self[TimelineVisibilityKey.self] }
        set { self[TimelineVisibilityKey.self] = newValue }
    }
}
#endif
