#if os(iOS)
import SwiftUI
import OCDesign
import OCSync
import OCModels

public struct HomeSessionRow: View {
    let item: SessionSummary
    let selected: Bool
    let select: () -> Void
    let review: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(item: SessionSummary, selected: Bool = false, select: @escaping () -> Void = {}, review: @escaping () -> Void = {}) {
        self.item = item; self.selected = selected; self.select = select; self.review = review
    }
    /// While the server is unreachable, running is only last known and idle rows say so.
    private var offline: Bool { item.server.readPath.offline }
    private var indicator: OCSessionIndicator.State {
        if item.needsYou { return item.failed ? .failed : .needsYou }
        if item.runningCount > 0 { return offline ? .staleRunning : .running }
        if item.session.unread { return .unread }
        if offline { return .offline }
        if item.server.readPath.lastStatusSync == nil { return .syncing }
        if case .connected = item.server.state { return .idle }
        return .syncing
    }
    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OCSpacing.sm) { primary; reviewButton }
            } else {
                HStack(alignment: .top, spacing: OCSpacing.sm) { primary; reviewButton }
            }
        }.accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var primary: some View {
        Button(action: select) {
                HStack(alignment: .top, spacing: OCSpacing.sm) {
                    OCProjectAvatar(item.projectName)
                    VStack(alignment: .leading, spacing: OCSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: OCSpacing.sm) {
                            Text(item.session.info.title ?? "Untitled session").font(OCType.small.weight(item.session.unread ? .semibold : .regular))
                                .foregroundStyle(OCColor.text).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Spacer(minLength: 0)
                            OCSessionIndicator(indicator)
                        }
                        Text(item.server.record.name + " · " + item.session.info.location.directory)
                            .font(OCType.micro).foregroundStyle(OCColor.textFaint)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).truncationMode(.middle)
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: OCSpacing.xs) { badges; cost }
                        } else {
                            HStack(spacing: OCSpacing.sm) { badges; Spacer(minLength: 0); cost }
                        }
                    }
                }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle()).ocHover()
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("homeSession-" + item.session.id)
    }
    @ViewBuilder private var badges: some View {
        if item.meta.pinned { OCBadge("Pinned") }
        if item.runningCount > 0 {
            Text(offline ? "Last seen running" : "\(item.runningCount) running").font(OCType.micro).foregroundStyle(OCColor.textMuted)
        } else if offline { Text("Offline").font(OCType.micro).foregroundStyle(OCColor.textMuted) }
        if item.session.unread { Text("Unread").font(OCType.micro).foregroundStyle(OCColor.info) }
    }
    private var cost: some View {
        Text(item.cost.formatted(.currency(code: "USD"))).font(OCType.micro).foregroundStyle(OCColor.textFaint)
    }
    @ViewBuilder private var reviewButton: some View {
        if item.needsYou {
            Button("Review", action: review).buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("review-" + item.session.id)
        }
    }
}
#endif
