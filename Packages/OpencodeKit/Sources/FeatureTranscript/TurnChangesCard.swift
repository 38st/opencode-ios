#if os(iOS)
import SwiftUI
import OCModels
import OCSync
import OCRender
import OCDesign

struct TurnChangesCard: View {
    let row: TimelineRow
    let model: TurnDiffModel
    let open: (String) -> Void
    @State private var expanded = false
    init(row: TimelineRow, model: TurnDiffModel, expanded: Bool = false, open: @escaping (String) -> Void) {
        self.row = row; self.model = model; self.open = open; _expanded = State(initialValue: expanded)
    }
    @Environment(\.timelineCellVisible) private var visible
    @Environment(\.dynamicTypeSize) private var typeSize
    private var paths: [String] { Array(Set(row.files).union(model.files.map(\.file))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.xs)) : AnyLayout(HStackLayout())
            header {
                Text(localized("\(paths.count) Changed files", comment: "Header of the files changed in a turn; %lld is the file count")).font(OCType.button)
                HStack {
                    if model.loaded {
                        Text(verbatim: "+\(FileDiff.totals(model.files).additions)").font(OCType.micro).foregroundStyle(OCColor.success)
                        Text(verbatim: "−\(FileDiff.totals(model.files).deletions)").font(OCType.micro).foregroundStyle(OCColor.danger)
                    }
                    Spacer(minLength: 0)
                    if paths.count > 5 { Button(expanded ? localized("Show less") : localized("Show all")) { expanded.toggle() }.buttonStyle(OCButtonStyle(.ghost)) }
                }
            }
            VStack(spacing: 0) {
            ForEach(Array((expanded ? paths : Array(paths.prefix(5))).enumerated()), id: \.element) { index, path in
                if index > 0 { Rectangle().fill(OCColor.border).frame(height: OCBorder.hairline) }
                Button { open(path) } label: {
                    HStack(spacing: OCSpacing.sm) {
                        OCFileIcon(path)
                        HStack(spacing: 0) {
                            let directory = (path as NSString).deletingLastPathComponent
                            if !directory.isEmpty { Text(directory + "/").foregroundStyle(OCColor.textMuted).truncationMode(.middle) }
                            Text((path as NSString).lastPathComponent).layoutPriority(1)
                        }.font(OCType.small).lineLimit(1)
                        Spacer(minLength: 0)
                        if let file = model.files.first(where: { $0.file == path }) {
                            if file.patch.isEmpty { Text(localized("Binary file")).font(OCType.micro).foregroundStyle(OCColor.textMuted) }
                            else if file.status == "added" || file.status == "deleted" {
                                Text(file.status == "added" ? localized("Created", comment: "File status: the file was created") : localized("Deleted", comment: "File status: the file was deleted")).font(OCType.micro).foregroundStyle(file.status == "added" ? OCColor.success : OCColor.danger)
                            } else {
                                Text(verbatim: "+\(file.additions)").font(OCType.micro).foregroundStyle(OCColor.success)
                                Text(verbatim: "−\(file.deletions)").font(OCType.micro).foregroundStyle(OCColor.danger)
                            }
                        }
                    }.padding(.horizontal, OCSpacing.sm).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("turnFile-" + path)
            }
            }.background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.md))
                .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
            if model.error != nil { Button(localized("Try again")) { model.load() }.buttonStyle(OCButtonStyle(.ghost)) }
        }.padding(.top, OCSpacing.md)
            .onAppear { if visible != false { model.load() } }
            .onChange(of: visible) { _, value in if value == true { model.load() } }
    }
}
#endif
