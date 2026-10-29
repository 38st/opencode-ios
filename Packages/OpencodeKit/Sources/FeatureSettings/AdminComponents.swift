#if os(iOS)
import SwiftUI
import OCDesign
import OCFoundation
import OCModels
import OCSync

/// Location-scoped screens read one project's location; this picks it.
struct AdminProjectPicker: View {
    @Bindable var admin: ServerAdminModel
    var body: some View {
        if admin.projects.count > 1 {
            Menu {
                Picker("Project", selection: Binding(get: { admin.directory ?? "" }, set: { admin.directory = $0 })) {
                    ForEach(admin.projects) { project in Text(AdminText.name(project)).tag(project.canonical) }
                }
            } label: {
                HStack(spacing: OCSpacing.sm) {
                    OCIcon("folder").foregroundStyle(OCColor.iconMuted)
                    Text(admin.project.map(AdminText.name) ?? "Choose a project").font(OCType.body).foregroundStyle(OCColor.text)
                    OCIcon("chevron-down", size: 12).foregroundStyle(OCColor.iconMuted)
                }.frame(minHeight: OCLayout.touchTarget)
            }.accessibilityLabel("Project: " + (admin.project.map(AdminText.name) ?? "none"))
                .accessibilityIdentifier("adminProjectPicker")
        } else if let project = admin.project {
            OCLabel(AdminText.name(project), icon: "folder").font(OCType.body).foregroundStyle(OCColor.textMuted)
        }
    }
}

/// Loading and empty states of one list.
struct AdminLoadState<Value: Sendable, Content: View>: View {
    let values: [Value]?
    let isLoading: Bool
    let empty: String
    var emptyDetail: String?
    @ViewBuilder let content: ([Value]) -> Content
    init(cell: Revalidating<[Value]>, empty: String, emptyDetail: String? = nil, @ViewBuilder content: @escaping ([Value]) -> Content) {
        values = cell.value; isLoading = cell.isLoading; self.empty = empty; self.emptyDetail = emptyDetail; self.content = content
    }
    var body: some View {
        if let values {
            if values.isEmpty {
                VStack(alignment: .leading, spacing: OCSpacing.xs) {
                    Text(empty).font(OCType.body)
                    if let emptyDetail { Text(emptyDetail).font(OCType.small).foregroundStyle(OCColor.textMuted) }
                }.accessibilityElement(children: .combine)
            } else { content(values) }
        } else if isLoading {
            HStack(spacing: OCSpacing.sm) { ProgressView(); Text("Loading…").font(OCType.body).foregroundStyle(OCColor.textMuted) }
        } else {
            Text("Not loaded. Pull to refresh.").font(OCType.body).foregroundStyle(OCColor.textMuted)
        }
    }
}
extension AdminLoadState where Value == JSONValue {
    /// Catalogs the composer shares keep the location's raw array.
    init(json cell: Revalidating<JSONValue>, empty: String, emptyDetail: String? = nil, @ViewBuilder content: @escaping ([JSONValue]) -> Content) {
        values = cell.value.map { $0.arrayValue ?? [] }; isLoading = cell.isLoading
        self.empty = empty; self.emptyDetail = emptyDetail; self.content = content
    }
}

/// A title, an optional explanation and trailing content, as the desktop's settings rows lay them out.
struct AdminRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var mono = false
    @ViewBuilder let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.sm))
            : AnyLayout(HStackLayout(spacing: OCSpacing.sm))
        layout {
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text(title).font(mono ? OCType.code : OCType.body).fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(OCType.small).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }.frame(minHeight: OCLayout.touchTarget)
    }
}
extension AdminRow where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, mono: Bool = false) { self.init(title: title, detail: detail, mono: mono) { EmptyView() } }
}

/// Failures and confirmations of the admin model, shown by every section.
struct AdminFeedback: ViewModifier {
    @Bindable var admin: ServerAdminModel
    func body(content: Content) -> some View {
        content
            .alert("Could not complete action", isPresented: Binding(get: { admin.error != nil }, set: { if !$0 { admin.error = nil } })) {
                Button("OK") { admin.error = nil }
            } message: { Text(admin.error ?? "") }
            .overlay(alignment: .bottom) {
                if let notice = admin.notice {
                    OCLabel(notice, icon: "circle-check").font(OCType.body).padding(OCSpacing.md)
                        .background(OCColor.layer2, in: Capsule()).padding(OCSpacing.lg)
                        .accessibilityIdentifier("adminNotice")
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(3))
                            if admin.notice == notice { admin.notice = nil }
                        }
                }
            }
    }
}

enum AdminText {
    static func name(_ project: Project) -> String { project.name ?? URL(fileURLWithPath: project.canonical).lastPathComponent }
    static func shortPath(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
    static func date(_ milliseconds: Double) -> String {
        Date(timeIntervalSince1970: milliseconds / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}
#endif
