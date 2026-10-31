#if os(iOS)
import SwiftUI
import OCDesign
import OCModels
import OCSync

/// Usage over whole days in the device's time zone (`GET /api/experimental/session/stats`), for every project or one.
struct UsageStatisticsSection: View {
    let server: ServerStore
    @State private var preset = StatsRange.Preset.week
    @State private var projectID: String?
    @State private var stats: SessionStats?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.md) {
                OCSegmentedControl(localized("Range", comment: "Date range for usage statistics"), options: StatsRange.Preset.allCases.map { ($0, $0.title) }, selection: $preset)
                    .accessibilityIdentifier("statsRange")
                if server.projects.count > 1 {
                    Menu {
                        Picker(localized("Project"), selection: $projectID) {
                            Text(localized("All projects")).tag(String?.none)
                            ForEach(server.projects) { project in Text(name(project)).tag(Optional(project.id)) }
                        }
                    } label: {
                        HStack(spacing: OCSpacing.sm) {
                            OCIcon("folder").foregroundStyle(OCColor.iconMuted)
                            Text(projectID.flatMap { id in server.projects.first { $0.id == id }.map(name) } ?? localized("All projects")).font(OCType.body).foregroundStyle(OCColor.text)
                            OCIcon("chevron-down", size: 12).foregroundStyle(OCColor.iconMuted)
                        }.frame(minHeight: OCLayout.touchTarget)
                    }.accessibilityIdentifier("statsProject")
                }
                Text(localized("Days in \(TimeZone.current.identifier)", comment: "%@ is a time zone identifier")).font(OCType.small).foregroundStyle(OCColor.textMuted)
            }
            if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).ocAnnounce(error, initial: true) }
            if let stats {
                if stats.isEmpty {
                    OCEmptyState(localized("No activity"), detail: localized("No sessions ran in this range."), icon: "window-analytics", presentation: .panel) { EmptyView() }
                        .accessibilityIdentifier("statsEmpty")
                } else { content(stats) }
            } else if loading { ProgressView(localized("Loading statistics…")).font(OCType.small) }
        }
        .task(id: Query(preset: preset, projectID: projectID)) { await load() }
        .refreshable { await load() }
    }
    private struct Query: Equatable { let preset: StatsRange.Preset; let projectID: String? }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let next = try await server.readPath.stats(StatsRange(preset, now: .now), projectID: projectID)
            try Task.checkCancellation(); stats = next; error = nil
        } catch is CancellationError {} catch {
            if !WriteErrorMessage.isCancellation(error) { self.error = localized("Could not load statistics. \(WriteErrorMessage.message(error))", comment: "%@ is the error message") }
        }
    }
    @ViewBuilder private func content(_ stats: SessionStats) -> some View {
        OCSection(localized("Activity")) {
            metric(localized("Sessions"), "\(stats.sessions)" + (stats.subagents > 0 ? " · " + localized("\(stats.subagents) subagents", comment: "%lld is the number of subagent sessions") : ""))
            metric(localized("Prompts"), "\(stats.prompts)")
            metric(localized("Steps"), "\(stats.steps)")
            metric(localized("Active days"), "\(stats.activeDays)")
            metric(localized("Best streak"), localized("\(stats.streak) days", comment: "%lld is the number of consecutive days"))
            if let busiest = stats.activity.max(by: { $0.steps < $1.steps }) { metric(localized("Busiest day"), busiest.date + " · " + localized("\(busiest.steps) steps", comment: "%lld is the number of agent steps")) }
        }.accessibilityIdentifier("statsActivity")
        OCSection(localized("Tokens and cost")) {
            metric(localized("Cost"), stats.cost.formatted(.currency(code: "USD")))
            metric(localized("Input", comment: "Input tokens"), count(stats.tokens.input))
            metric(localized("Output", comment: "Output tokens"), count(stats.tokens.output))
            if stats.tokens.reasoning > 0 { metric(localized("Reasoning", comment: "Reasoning tokens"), count(stats.tokens.reasoning)) }
            metric(localized("Cache read · write", comment: "Tokens read from and written to the cache"), count(stats.tokens.cacheRead) + " · " + count(stats.tokens.cacheWrite))
        }
        OCSection(localized("Tools")) {
            metric(localized("Calls", comment: "Number of tool calls"), "\(stats.tools.calls)")
            metric(localized("Succeeded · failed", comment: "Tool call outcomes"), "\(stats.tools.succeeded) · \(stats.tools.failed)" + (stats.tools.unfinished > 0 ? " · " + localized("\(stats.tools.unfinished) unfinished", comment: "%lld is the number of unfinished tool calls") : ""))
            ForEach(Array(stats.tools.byTool.prefix(8).enumerated()), id: \.offset) { _, tool in
                metric(tool.name, "\(tool.calls)" + (tool.failed > 0 ? " · " + localized("\(tool.failed) failed", comment: "%lld is the number of failed tool calls") : ""))
            }
        }
        if !stats.models.isEmpty {
            OCSection(localized("Models")) {
                ForEach(Array(stats.models.sorted { $0.steps > $1.steps }.enumerated()), id: \.offset) { _, model in
                    metric(model.model.id, localized("\(model.steps) steps", comment: "%lld is the number of agent steps") + " · " + model.cost.formatted(.currency(code: "USD")))
                }
            }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(OCType.body).foregroundStyle(OCColor.textMuted)
            Spacer(minLength: OCSpacing.md)
            Text(value).font(OCType.body).multilineTextAlignment(.trailing)
        }.accessibilityElement(children: .combine)
    }
    private func count(_ value: Double) -> String { Int(value).formatted(.number.notation(.compactName)) }
    private func name(_ project: Project) -> String { project.name ?? (project.canonical as NSString).lastPathComponent }
}
#endif
