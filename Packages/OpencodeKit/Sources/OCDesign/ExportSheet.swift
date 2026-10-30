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
                OCSegmentedControl("Format", options: [(ExportFormat.markdown, "Markdown"), (ExportFormat.json, "JSON")], selection: $format)
                    .accessibilityIdentifier("exportFormat")
                OCToggleRow("Redact content", detail: "Replace titles, paths, prompts, replies and tool output with placeholders, to share a transcript’s shape without its content.",
                            isOn: $sanitize).accessibilityIdentifier("exportSanitize")
                if let file {
                    ShareLink(item: file) { OCLabel("Share " + file.lastPathComponent, icon: "share") }
                        .buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("exportShare")
                } else if error == nil {
                    ProgressView("Preparing export…").font(OCType.small)
                }
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).ocAnnounce(error, initial: true) }
            }.navigationTitle("Export session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: close).accessibilityIdentifier("closeExport") } }
        }.ocTheme()
            .task(id: Options(format: format, sanitize: sanitize)) {
                file = nil; error = nil
                do { let next = try await prepare(format, sanitize); try Task.checkCancellation(); file = next }
                catch is CancellationError {} catch { self.error = "Failed to export session. " + error.localizedDescription }
            }
    }
    private struct Options: Equatable { let format: ExportFormat; let sanitize: Bool }
}
#endif
