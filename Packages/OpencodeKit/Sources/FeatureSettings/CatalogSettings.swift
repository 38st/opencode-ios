#if os(iOS)
import SwiftUI
import OCDesign
import OCFoundation
import OCModels
import OCSync

/// The location's agents, commands, skills, plugins and references, read-only except plugin updates.
struct CatalogSection: View {
    enum Tab: String, CaseIterable { case agents = "Agents", commands = "Commands", skills = "Skills", plugins = "Plugins", references = "References"
        var title: String {
            switch self {
            case .agents: localized("Agents")
            case .commands: localized("Commands")
            case .skills: localized("Skills")
            case .plugins: localized("Plugins")
            case .references: localized("References")
            }
        }
    }
    @Bindable var admin: ServerAdminModel
    @State private var tab: Tab = .agents
    @State private var updating: [String]?
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                AdminProjectPicker(admin: admin)
                ScrollView(.horizontal, showsIndicators: false) {
                    OCSegmentedControl(localized("Catalog"), options: Tab.allCases.map { ($0, $0.title) }, selection: $tab, equalWidth: false)
                }
            }
            if let catalog = admin.catalog {
                switch tab {
                case .agents: agents(catalog)
                case .commands: commands(catalog)
                case .skills: skills(catalog)
                case .plugins: plugins
                case .references: references(catalog)
                }
            }
        }
        .task(id: admin.directory) { await admin.loadCatalogs() }
        .task(id: tab == .plugins ? admin.directory : nil) { if tab == .plugins { await admin.loadPlugins() } }
        .refreshable {
            admin.catalog?.invalidate(); admin.plugins.invalidate()
            await admin.loadCatalogs(); if tab == .plugins { await admin.loadPlugins() }
        }
        .confirmationDialog(updating?.count == 1 ? localized("Update \(updating?.first ?? "")?", comment: "%@ is a plugin name") : localized("Update \(updating?.count ?? 0) plugins?", comment: "%lld is the number of plugins"),
                            isPresented: Binding(get: { updating != nil }, set: { if !$0 { updating = nil } }), titleVisibility: .visible) {
            Button(localized("Update", comment: "Verb: update plugins")) {
                guard let targets = updating else { return }
                updating = nil
                task = Task { await admin.updatePlugins(targets) }
            }.accessibilityIdentifier("confirmUpdatePlugins")
        } message: {
            Text(localized("The server installs the newest version of \((updating ?? []).joined(separator: ", ")) and reloads it for every project.", comment: "%@ is a list of plugin names"))
        }
        .onDisappear { task?.cancel() }
    }
    private func agents(_ catalog: LocationCatalog) -> some View {
        OCSection(localized("Agents")) {
            AdminLoadState(cell: catalog.agents, empty: localized("No agents")) { (agents: [AgentInfo]) in
                ForEach(agents.filter { !$0.hidden }) { agent in
                    NavigationLink { AgentDetailView(agent: agent) } label: {
                        AdminRow(title: agent.name, detail: Self.agentSummary(agent)) {
                            OCBadge(agent.mode == "all" ? localized("primary and subagent", comment: "Agent mode badge") : agent.mode)
                            OCIcon("chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("agent-" + agent.id)
                }
            }
        }
    }
    static func agentSummary(_ agent: AgentInfo) -> String {
        var parts: [String] = []
        if let description = agent.description { parts.append(description) }
        if let model = agent.model { parts.append(localized("Model: \(model.providerID + "/" + model.id)", comment: "%@ is a provider/model id")) }
        if let steps = agent.steps { parts.append(localized("Up to \(Int(steps)) steps", comment: "%lld is the maximum number of agent steps")) }
        parts.append(PermissionSummary.line(agent.permissions))
        return parts.joined(separator: "\n")
    }
    private func commands(_ catalog: LocationCatalog) -> some View {
        OCSection(localized("Commands")) {
            AdminLoadState(json: catalog.commands, empty: localized("No commands")) { (values: [JSONValue]) in
                ForEach(values.map(CommandInfo.init(raw:))) { command in
                    AdminRow("/" + command.name, detail: command.description, mono: true)
                }
            }
        }
    }
    private func skills(_ catalog: LocationCatalog) -> some View {
        OCSection(localized("Skills")) {
            AdminLoadState(json: catalog.skills, empty: localized("No skills yet"), emptyDetail: localized("Skills available to opencode will appear here.")) { (values: [JSONValue]) in
                ForEach(values.map(SkillInfo.init(raw:))) { skill in
                    NavigationLink {
                        OCForm {
                            if let description = skill.description { Text(description).foregroundStyle(OCColor.textMuted) }
                            Text(skill.path).font(OCType.code).foregroundStyle(OCColor.textMuted).textSelection(.enabled)
                            StreamingMarkdownView(skill.content)
                        }.ocNavigationTitle(skill.name)
                    } label: {
                        AdminRow(title: skill.name, detail: skill.description) {
                            if !skill.autoinvoke { OCBadge(localized("On request", comment: "Badge: skill runs only when requested")) }
                            OCIcon("chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("skill-" + skill.name)
                }
            }
        }
    }
    @ViewBuilder private var plugins: some View {
        OCSection(localized("Plugins")) {
            AdminLoadState(cell: admin.plugins, empty: localized("No plugins yet")) { (plugins: [PluginInfo]) in
                let outdated = plugins.filter(\.outdated).compactMap(\.target)
                if !outdated.isEmpty {
                    Button(localized("Update all (\(outdated.count))", comment: "%lld is the number of outdated plugins")) { updating = outdated }.buttonStyle(OCButtonStyle(.contrast))
                        .disabled(admin.isBusy("plugins:update"))
                }
                ForEach(plugins.sorted { ($0.sourceType == "builtin" ? 1 : 0, $0.id) < ($1.sourceType == "builtin" ? 1 : 0, $1.id) }) { plugin in
                    AdminRow(title: plugin.id, detail: Self.pluginDetail(plugin)) {
                        if let failure = plugin.failure { OCBadge(localized("Failed"), tone: .danger).accessibilityLabel(localized("Failed: \(failure)", comment: "%@ is the failure message")) }
                        else if plugin.updating { OCBadge(localized("Updating"), tone: .info) }
                        else if plugin.outdated, let target = plugin.target {
                            Button(localized("Update", comment: "Verb: update plugins")) { updating = [target] }.buttonStyle(OCButtonStyle()).disabled(admin.isBusy("plugins:update"))
                        }
                    }
                }
            }
            Button { task = Task { await admin.checkPlugins() } } label: { OCLabel(localized("Check for updates"), icon: "refresh") }
                .buttonStyle(OCButtonStyle()).disabled(admin.isBusy("plugins:check")).accessibilityIdentifier("checkPlugins")
        }
    }
    static func pluginDetail(_ plugin: PluginInfo) -> String {
        var parts = [plugin.sourceType == "builtin" ? localized("Built in") : plugin.sourceType == "local" ? (plugin.path ?? localized("Local", comment: "Plugin source: local files")) : (plugin.version.map { localized("Version \($0)", comment: "%@ is a version number") } ?? plugin.sourceType)]
        if !plugin.features.isEmpty { parts.append(plugin.features.joined(separator: ", ")) }
        if let failure = plugin.failure { parts.append(failure) }
        return parts.joined(separator: " · ")
    }
    private func references(_ catalog: LocationCatalog) -> some View {
        OCSection(localized("References")) {
            AdminLoadState(json: catalog.references, empty: localized("No references"), emptyDetail: localized("Add references in opencode.json to @-mention other folders and repositories.")) { (values: [JSONValue]) in
                ForEach(values.map(ReferenceInfo.init(raw:)).filter { !$0.hidden }) { reference in
                    AdminRow("@" + reference.name, detail: [reference.description, reference.source].compactMap { $0 }.joined(separator: "\n"), mono: true)
                }
            }
        }
    }
}

/// One agent's rules, in evaluation order: the last matching rule wins.
struct AgentDetailView: View {
    let agent: AgentInfo
    var body: some View {
        OCForm {
            if let description = agent.description { Text(description).foregroundStyle(OCColor.textMuted) }
            OCSection(localized("Agent")) {
                LabeledContent(localized("Mode"), value: agent.mode)
                if let model = agent.model { LabeledContent(localized("Model"), value: model.providerID + "/" + model.id) }
                if let steps = agent.steps { LabeledContent(localized("Steps"), value: String(Int(steps))) }
                if let color = agent.color { LabeledContent(localized("Colour"), value: color) }
            }.font(OCType.body)
            OCSection(localized("Permissions")) {
                Text(localized("Rules apply in order; the last one that matches decides.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                ForEach(Array(agent.permissions.enumerated()), id: \.offset) { _, rule in
                    AdminRow(title: rule.action + "  " + rule.resource, mono: true) {
                        OCBadge(rule.effect, tone: rule.effect == "deny" ? .danger : rule.effect == "ask" ? .warning : .success)
                    }
                }
            }
        }.ocNavigationTitle(agent.name)
    }
}

enum PermissionSummary {
    /// "Asks before edit · denies browser": the effective rule of each action that is not allowed everywhere.
    static func line(_ rules: [PermissionRule]) -> String {
        var effective: [String: String] = [:], order: [String] = []
        for rule in rules where rule.resource == "*" {
            if effective[rule.action] == nil { order.append(rule.action) }
            effective[rule.action] = rule.effect
        }
        let asks = order.filter { effective[$0] == "ask" && $0 != "*" }, denies = order.filter { effective[$0] == "deny" && $0 != "*" }
        var parts: [String] = [effective["*"] == "deny" ? localized("Denies by default") : effective["*"] == "ask" ? localized("Asks by default") : localized("Allows by default")]
        if !asks.isEmpty { parts.append(localized("asks before \(asks.joined(separator: ", "))", comment: "%@ is a list of tool names")) }
        if !denies.isEmpty { parts.append(localized("denies \(denies.joined(separator: ", "))", comment: "%@ is a list of tool names")) }
        return parts.joined(separator: " · ")
    }
}
#endif
