#if os(iOS)
import SwiftUI
import CoreImage.CIFilterBuiltins
import OCDesign
import OCFoundation
import OCModels
import OCSync
import FeatureApprovals

// Wording: packages/app/src/settings/providers/ and providers/connect/ at v2.2.1.
struct ProvidersSection: View {
    @Bindable var admin: ServerAdminModel
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text(localized("Manage provider connections and the accounts used for each provider.")).foregroundStyle(OCColor.textMuted)
                AdminProjectPicker(admin: admin)
            }
            AdminLoadState(cell: admin.integrations, empty: localized("No providers found")) { (integrations: [IntegrationInfo]) in
                let connected = integrations.filter(\.isConnected), available = integrations.filter { !$0.isConnected }
                OCSection(localized("Connected providers")) {
                    if connected.isEmpty { Text(localized("No providers connected")).foregroundStyle(OCColor.textMuted) }
                    ForEach(connected) { row($0) }
                }
                if !available.isEmpty { OCSection(localized("Available", comment: "Section of providers not yet connected")) { ForEach(available) { row($0) } } }
            }
            Text(localized("Credentials are stored on the server, never on this device. Models from a connected provider become available on this server."))
                .font(OCType.small).foregroundStyle(OCColor.textMuted)
        }
        .task(id: admin.directory) { await admin.loadIntegrations() }
        .refreshable { admin.integrations.invalidate(); await admin.loadIntegrations() }
    }
    private func row(_ integration: IntegrationInfo) -> some View {
        NavigationLink { ProviderDetailView(admin: admin, integrationID: integration.id) } label: {
            AdminRow(title: integration.name, detail: summary(integration)) {
                if integration.needsAuth { OCBadge(localized("Needs sign-in"), tone: .warning) }
                else if integration.isConnected { OCBadge(localized("Connected"), tone: .success) }
                OCIcon("chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("provider-" + integration.id)
    }
    private func summary(_ integration: IntegrationInfo) -> String {
        var parts: [String] = []
        if let active = integration.accounts.first { parts.append(active.label) }
        if integration.accounts.count > 1 { parts.append(localized("\(integration.accounts.count) accounts", comment: "%lld is the number of provider accounts")) }
        if !integration.environment.isEmpty { parts.append(localized("Environment", comment: "Credential comes from environment variables")) }
        if parts.isEmpty { parts.append(integration.methods.map(\.label).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

struct ProviderDetailView: View {
    @Bindable var admin: ServerAdminModel
    let integrationID: String
    @State private var keyMethod: IntegrationMethod?
    @State private var renaming: IntegrationConnection?
    @State private var newLabel = ""
    @State private var removing: IntegrationConnection?
    @State private var task: Task<Void, Never>?
    private var integration: IntegrationInfo? { admin.integrations.value?.first { $0.id == integrationID } }
    var body: some View {
        OCForm {
            if let integration {
                if !integration.accounts.isEmpty {
                    OCSection(localized("Connected accounts")) {
                        ForEach(Array(integration.accounts.enumerated()), id: \.element.id) { index, account in accountRow(account, active: index == 0, integration: integration) }
                    }
                }
                if !integration.environment.isEmpty {
                    OCSection(localized("Environment", comment: "Credential comes from environment variables")) {
                        ForEach(integration.environment) { connection in
                            AdminRow(connection.name, detail: localized("Set in the server's environment. Change it on the computer running opencode."), mono: true)
                        }
                    }
                }
                OCSection(integration.accounts.isEmpty ? localized("Connect") : localized("Add account")) {
                    ForEach(integration.methods) { method in methodRow(method, integration: integration) }
                }
            } else {
                Text(localized("This provider is no longer available on the server.")).foregroundStyle(OCColor.textMuted)
            }
        }
        .ocNavigationTitle(integration?.name ?? localized("Provider"))
        .sheet(item: $keyMethod) { method in
            if let integration { KeyConnectSheet(admin: admin, integration: integration, method: method).ocSheet() }
        }
        .sheet(isPresented: Binding(get: { admin.connect?.integrationID == integrationID }, set: { if !$0 { admin.endConnect() } })) {
            if let flow = admin.connect { ConnectFlowView(flow: flow) { admin.endConnect() }.ocSheet() }
        }
        .alert(localized("Rename account"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(localized("Account name"), text: $newLabel)
            Button(localized("Cancel"), role: .cancel) { renaming = nil }
            Button(localized("Rename")) {
                guard let account = renaming else { return }
                renaming = nil
                task = Task { _ = await admin.rename(account, label: newLabel) }
            }
        }
        .confirmationDialog(removing.map { localized("Remove \($0.label)?", comment: "%@ is an account name") } ?? localized("Remove account?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button(localized("Remove"), role: .destructive) {
                guard let account = removing else { return }
                removing = nil
                task = Task { _ = await admin.remove(account) }
            }.accessibilityIdentifier("confirmRemoveAccount")
        } message: {
            Text(removalMessage)
        }
        .onDisappear { task?.cancel() }
    }
    private var removalMessage: String {
        guard let integration, let removing else { return "" }
        return integration.accounts.count == 1
            ? localized("This deletes the credential from the server. \(integration.name) models will no longer be available.", comment: "%@ is a provider name")
            : localized("This deletes the credential \(removing.label) from the server.", comment: "%@ is an account name")
    }
    private func accountRow(_ account: IntegrationConnection, active: Bool, integration: IntegrationInfo) -> some View {
        AdminRow(title: account.label, detail: [account.method == "oauth" ? localized("Signed in") : account.method == "key" ? localized("API key") : localized("External", comment: "Account managed outside opencode"),
                                              account.needsAuth?.message].compactMap { $0 }.joined(separator: " · ")) {
            if active { OCBadge(localized("Active", comment: "Badge: the account in use"), tone: .success) }
            if account.needsAuth != nil { OCBadge(localized("Needs sign-in"), tone: .warning) }
            Menu {
                if !active {
                    Button(localized("Use this account")) { task = Task { _ = await admin.activate(account) } }
                }
                Button(localized("Rename")) { newLabel = account.label; renaming = account }
                Button(localized("Remove"), role: .destructive) { removing = account }
            } label: {
                OCIcon("outline-dots").foregroundStyle(OCColor.iconMuted)
                    .frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget).contentShape(Rectangle())
            }.accessibilityLabel(localized("\(account.label) options", comment: "%@ is an account name")).accessibilityIdentifier("accountMenu-" + account.label)
        }
    }
    @ViewBuilder private func methodRow(_ method: IntegrationMethod, integration: IntegrationInfo) -> some View {
        switch method.type {
        case "key", "oauth", "command":
            Button {
                if method.type == "key" { keyMethod = method } else { admin.beginConnect(integration, method: method) }
            } label: {
                OCLabel(method.type == "key" ? localized("Connect with an API key") : method.label, icon: method.type == "key" ? "lock" : "link")
            }.buttonStyle(OCButtonStyle()).disabled(admin.isBusy("connect:" + integration.id))
                .accessibilityIdentifier("connectMethod-" + method.type)
        case "env":
            AdminRow(localized("Environment variable"), detail: localized("Set \(method.names.formatted(.list(type: .or))) on the computer running opencode.", comment: "%@ is a list of environment variable names"))
        default:
            AdminRow(method.label, detail: localized("Set up on the computer running opencode."))
        }
    }
}

/// An API key, the method's questions and an optional account name. The key is cleared after every submit.
struct KeyConnectSheet: View {
    @Bindable var admin: ServerAdminModel
    let integration: IntegrationInfo
    let method: IntegrationMethod
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var label = ""
    @State private var answers: [String: JSONValue] = [:]
    @State private var showErrors = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            OCForm {
                Text(localized("Enter your \(integration.name) API key to connect your account and use \(integration.name) models on this server.", comment: "Both %@ are the provider name"))
                    .foregroundStyle(OCColor.textMuted)
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text(localized("\(integration.name) API key", comment: "%@ is a provider name")).font(OCType.heading)
                    SecureField(localized("API key"), text: $key).textContentType(.password).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().accessibilityIdentifier("providerAPIKey")
                    if showErrors && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(localized("API key is required")).font(OCType.small).foregroundStyle(OCColor.danger)
                    }
                }
                if let form = method.form { FormRenderer(form: form, answers: $answers, showErrors: showErrors) }
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text(localized("Account name (optional)")).font(OCType.heading)
                    TextField(localized("Account name"), text: $label).accessibilityIdentifier("providerAccountLabel")
                }
                Button(localized("Connect")) { submit() }.buttonStyle(OCButtonStyle(.contrast))
                    .disabled(admin.isBusy("connect:" + integration.id)).accessibilityIdentifier("submitProviderKey")
                Text(localized("The key is sent to the server once and is not kept on this device.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
            }
            .ocNavigationTitle(localized("Connect \(integration.name)", comment: "%@ is a provider name"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(localized("Cancel")) { key = ""; dismiss() } } }
        }
        .onDisappear { key = ""; task?.cancel() }
    }
    private func submit() {
        let errors = method.form.map { FormValidation.errors($0, answers: answers) } ?? [:]
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, errors.isEmpty else { showErrors = true; return }
        let secret = key, form = method.form
        key = ""
        let active = form.map { FormValidation.activeAnswers($0, answers: answers) } ?? [:]
        task = Task {
            let connected = await admin.connectKey(integration, key: secret, answers: active.isEmpty ? nil : .object(active),
                                                   label: label.isEmpty ? nil : label)
            if connected { dismiss() }
        }
    }
}

/// OAuth (a pasted code, or the server finishing by itself) and login commands.
struct ConnectFlowView: View {
    let flow: ConnectFlow
    let done: () -> Void
    @State private var code = ""
    @State private var showQR = false
    var body: some View {
        NavigationStack {
            OCForm {
                switch flow.phase {
                case .starting:
                    progress(localized("Opening sign-in…"))
                case .code(let attempt):
                    Text(localized("Your browser opens so you can sign in to \(flow.integrationName). Paste the authorization code it gives you below.", comment: "%@ is a provider name"))
                    link(attempt)
                    TextField(localized("Authorization code"), text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("oauthCode")
                    Button(localized("Continue")) { flow.submit(code: code); code = "" }.buttonStyle(OCButtonStyle(.contrast))
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                case .waiting(let attempt):
                    Text(localized("Finish signing in to \(flow.integrationName) in a browser. If the page sends you to localhost, open the link on the computer running opencode: that is where the server listens for the answer.", comment: "%@ is a provider name"))
                    link(attempt)
                    progress(localized("Waiting for authorization…"))
                case .command(let message):
                    Text(localized("opencode is running \(flow.method.label) on the server. Follow its instructions there or below.", comment: "%@ is a login method name"))
                    if let message, !message.isEmpty {
                        Text(message).font(OCType.code).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("commandMessage")
                    }
                    progress(localized("Waiting for command to finish…"))
                case .completing:
                    progress(localized("Authorization in progress…"))
                case .complete:
                    OCLabel(localized("\(flow.integrationName) connected", comment: "%@ is a provider name"), icon: "circle-check").font(OCType.heading)
                case .failed(let message):
                    Text(localized("Authorization failed: \(message)", comment: "%@ is the error message")).foregroundStyle(OCColor.danger).accessibilityIdentifier("connectFailed")
                case .expired:
                    Text(localized("Authorization expired. Start again for a new link.")).foregroundStyle(OCColor.danger)
                case .cancelled:
                    Text(localized("Sign-in cancelled.")).foregroundStyle(OCColor.textMuted)
                }
            }
            .ocNavigationTitle(localized("Connect \(flow.integrationName)", comment: "%@ is a provider name"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(flow.phase.isFinished ? localized("Done") : localized("Cancel")) { flow.cancel(); done() }.accessibilityIdentifier("closeConnect")
                }
            }
        }
    }
    private func progress(_ text: String) -> some View {
        HStack(spacing: OCSpacing.sm) { ProgressView(); Text(text).foregroundStyle(OCColor.textMuted) }
    }
    @ViewBuilder private func link(_ attempt: OAuthAttempt) -> some View {
        if !attempt.instructions.isEmpty { Text(attempt.instructions).font(OCType.body).textSelection(.enabled) }
        Text(attempt.url).font(OCType.code).textSelection(.enabled).lineLimit(4).accessibilityIdentifier("oauthURL")
        if let url = URL(string: attempt.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OCSpacing.sm) { linkActions(url) }
                VStack(alignment: .leading, spacing: OCSpacing.sm) { linkActions(url) }
            }
            if showQR, let image = QRCode.image(attempt.url) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240)
                    .accessibilityLabel(localized("QR code of the sign-in link"))
            }
        }
    }
    @ViewBuilder private func linkActions(_ url: URL) -> some View {
        Link(destination: url) { OCLabel(localized("Open link"), icon: "square-arrow-top-right") }.buttonStyle(OCButtonStyle())
        Button { OCCopy.text(url.absoluteString) } label: { OCLabel(localized("Copy", comment: "Verb: copy the link"), icon: "copy") }.buttonStyle(OCButtonStyle(.ghost))
        ShareLink(item: url) { OCLabel(localized("Share", comment: "Verb: share the link"), icon: "share") }.buttonStyle(OCButtonStyle(.ghost))
        Button { showQR.toggle() } label: { OCLabel(showQR ? localized("Hide QR code") : localized("Show QR code"), icon: "grid-plus") }.buttonStyle(OCButtonStyle(.ghost))
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
