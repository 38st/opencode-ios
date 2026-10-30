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
                OCSegmentedControl("Range", options: StatsRange.Preset.allCases.map { ($0, $0.title) }, selection: $preset)
                    .accessibilityIdentifier("statsRange")
                if server.projects.count > 1 {
                    Menu {
                        Picker("Project", selection: $projectID) {
                            Text("All projects").tag(String?.none)
                            ForEach(server.projects) { project in Text(name(project)).tag(Optional(project.id)) }
                        }
                    } label: {
                        HStack(spacing: OCSpacing.sm) {
                            OCIcon("folder").foregroundStyle(OCColor.iconMuted)
                            Text(projectID.flatMap { id in server.projects.first { $0.id == id }.map(name) } ?? "All projects").font(OCType.body).foregroundStyle(OCColor.text)
                            OCIcon("chevron-down", size: 12).foregroundStyle(OCColor.iconMuted)
                        }.frame(minHeight: OCLayout.touchTarget)
                    }.accessibilityIdentifier("statsProject")
                }
                Text("Days in " + TimeZone.current.identifier).font(OCType.small).foregroundStyle(OCColor.textMuted)
            }
            if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).ocAnnounce(error, initial: true) }
            if let stats {
                if stats.isEmpty {
                    OCEmptyState("No activity", detail: "No sessions ran in this range.", icon: "window-analytics", presentation: .panel) { EmptyView() }
                        .accessibilityIdentifier("statsEmpty")
                } else { content(stats) }
            } else if loading { ProgressView("Loading statistics…").font(OCType.small) }
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
            if !WriteErrorMessage.isCancellation(error) { self.error = "Could not load statistics. " + WriteErrorMessage.message(error) }
        }
    }
    @ViewBuilder private func content(_ stats: SessionStats) -> some View {
        OCSection("Activity") {
            metric("Sessions", "\(stats.sessions)" + (stats.subagents > 0 ? " · \(stats.subagents) subagents" : ""))
            metric("Prompts", "\(stats.prompts)")
            metric("Steps", "\(stats.steps)")
            metric("Active days", "\(stats.activeDays)")
            metric("Best streak", "\(stats.streak) " + (stats.streak == 1 ? "day" : "days"))
            if let busiest = stats.activity.max(by: { $0.steps < $1.steps }) { metric("Busiest day", busiest.date + " · \(busiest.steps) steps") }
        }.accessibilityIdentifier("statsActivity")
        OCSection("Tokens and cost") {
            metric("Cost", stats.cost.formatted(.currency(code: "USD")))
            metric("Input", count(stats.tokens.input))
            metric("Output", count(stats.tokens.output))
            if stats.tokens.reasoning > 0 { metric("Reasoning", count(stats.tokens.reasoning)) }
            metric("Cache read · write", count(stats.tokens.cacheRead) + " · " + count(stats.tokens.cacheWrite))
        }
        OCSection("Tools") {
            metric("Calls", "\(stats.tools.calls)")
            metric("Succeeded · failed", "\(stats.tools.succeeded) · \(stats.tools.failed)" + (stats.tools.unfinished > 0 ? " · \(stats.tools.unfinished) unfinished" : ""))
            ForEach(Array(stats.tools.byTool.prefix(8).enumerated()), id: \.offset) { _, tool in
                metric(tool.name, "\(tool.calls)" + (tool.failed > 0 ? " · \(tool.failed) failed" : ""))
            }
        }
        if !stats.models.isEmpty {
            OCSection("Models") {
                ForEach(Array(stats.models.sorted { $0.steps > $1.steps }.enumerated()), id: \.offset) { _, model in
                    metric(model.model.id, "\(model.steps) steps · " + model.cost.formatted(.currency(code: "USD")))
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
