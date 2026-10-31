#if os(iOS)
import SwiftUI
import OCModels

/// Exports a transcript: the server's JSON, sanitised by default, or Markdown. The file is shared through the share
/// sheet from a temporary folder; nothing is written to the App Group.
public struct OCExportSheet: View {
    let prepare: (ExportFormat, Bool) async throws -> URL
    let close: () -> Void
    @State private var format = ExportFormat.markdown
    @State private var sanitize = true
    @State private var file: URL?
    @State private var error: String?
    public init(prepare: @escaping (ExportFormat, Bool) async throws -> URL, close: @escaping () -> Void) {
        self.prepare = prepare; self.close = close
    }
    public var body: some View {
        NavigationStack {
            OCForm {
                OCSegmentedControl(localized("Format", comment: "Noun: export file format picker"), options: [(ExportFormat.markdown, "Markdown"), (ExportFormat.json, "JSON")], selection: $format)
                    .accessibilityIdentifier("exportFormat")
                OCToggleRow(localized("Redact content"), detail: localized("Replace titles, paths, prompts, replies and tool output with placeholders, to share a transcript’s shape without its content."),
                            isOn: $sanitize).accessibilityIdentifier("exportSanitize")
                if let file {
                    ShareLink(item: file) { OCLabel(localized("Share \(file.lastPathComponent)", comment: "%@ is the exported file name"), icon: "share") }
                        .buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("exportShare")
                } else if error == nil {
                    ProgressView(localized("Preparing export…")).font(OCType.small)
                }
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).ocAnnounce(error, initial: true) }
            }.navigationTitle(localized("Export session")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(localized("Done"), action: close).accessibilityIdentifier("closeExport") } }
        }.ocTheme()
            .task(id: Options(format: format, sanitize: sanitize)) {
                file = nil; error = nil
                do { let next = try await prepare(format, sanitize); try Task.checkCancellation(); file = next }
                catch is CancellationError {} catch { self.error = localized("Failed to export session. \(error.localizedDescription)", comment: "%@ is the system error description") }
            }
    }
    private struct Options: Equatable { let format: ExportFormat; let sanitize: Bool }
}
#endif
