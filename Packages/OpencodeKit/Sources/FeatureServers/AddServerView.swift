#if os(iOS)
import SwiftUI
import OCDesign
import Observation
import OCSync
import OCModels
import VisionKit
import Vision

struct AddServerView: View {
    let registry: ServerRegistry
    var repairing: ServerStore?
    let completed: (ServerStore) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var method = 0
    @State private var copiedPairCommand = false
    @State private var name = ""
    @State private var address = ""
    @State private var password = ""
    @State private var link = ""
    @State private var error: String?
    @State private var working = false
    @State private var explainLocal = false
    @State private var scanning = false
    @State private var scannerError: String?
    @State private var task: Task<Void, Never>?
    @State private var connecting: ServerStore?
    @State private var finished = false
    init(registry: ServerRegistry, repairing: ServerStore? = nil, initialMethod: Int = 0, completed: @escaping (ServerStore) -> Void) {
        self.registry = registry; self.repairing = repairing; self.completed = completed
        _method = State(initialValue: initialMethod)
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: OCSpacing.lg) {
                        OCIcon("server", size: 32).foregroundStyle(OCColor.iconMuted).accessibilityHidden(true)
                        VStack(spacing: OCSpacing.sm) {
                            Text(repairing == nil ? "Connect to a server" : "Re-pair server").font(OCType.title)
                            Text(method == 0 ? "Paste the pairing link from the server, or scan its QR code." : "Enter your server address and password to get started.")
                                .font(OCType.small).foregroundStyle(OCColor.textMuted)
                        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.bottom, OCSpacing.lg)
                        if let repairing {
                            OCBanner("Needs re-pairing", tone: .warning)
                            if repairing.tokenExpiresSoon {
                                Text("Your pairing token expires within 5 days. Pair again to stay connected.")
                                    .font(OCType.small).foregroundStyle(OCColor.warning)
                            }
                        }
                        if method == 0 {
                            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                                Text("Pairing link").font(OCType.button)
                                TextField("Pairing link", text: $link, prompt: Text(verbatim: "http://192.168.1.2:4096/auth/connect/…").foregroundStyle(OCColor.textFaint), axis: .vertical)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityLabel("Pairing link").accessibilityIdentifier("pairingLink")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: OCSpacing.md) {
                                if repairing == nil {
                                    Text("Name (optional)").font(OCType.button)
                                    TextField("Studio Mac", text: $name).accessibilityLabel("Name (optional)").accessibilityIdentifier("serverName")
                                }
                                Text("Server URL").font(OCType.button)
                                TextField("Server URL", text: $address, prompt: Text(verbatim: "http://192.168.1.2:4096").foregroundStyle(OCColor.textFaint)).keyboardType(.URL)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityLabel("Server URL").accessibilityIdentifier("serverURL")
                                Text("Password").font(OCType.button)
                                SecureField("Password", text: $password).textContentType(.password).accessibilityIdentifier("serverPassword")
                                if address.lowercased().hasPrefix("http://") {
                                    OCLabel("Unencrypted: anyone on this network may be able to read your credential. Prefer HTTPS on networks you don’t trust.", icon: "lock")
                                        .font(OCType.small).foregroundStyle(OCColor.textMuted)
                                }
                            }
                        }
                        if let error { OCBanner(error, tone: .danger).accessibilityIdentifier("setupError").ocAnnounce(error, initial: true) }
                        if working {
                            OCSpinner(method == 0 ? "Pairing with server…" : "Connecting to server…").accessibilityIdentifier("pairingProgress")
                        } else {
                            Button { connectTapped() } label: { Text(repairing == nil ? "Connect" : "Pair again").frame(maxWidth: .infinity) }
                                .buttonStyle(OCButtonStyle(.contrast))
                                .disabled(method == 0 ? link.isEmpty : address.isEmpty).accessibilityIdentifier("connectServer")
                        }
                        if method == 0 && DataScannerViewController.isSupported {
                            Button { scanning = true } label: { Text("Scan QR code").frame(maxWidth: .infinity) }
                                .buttonStyle(OCButtonStyle()).accessibilityIdentifier("scanPairingCode")
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: OCSpacing.xs) { methodSwitch }
                            VStack(spacing: 0) { methodSwitch }
                        }
                        if method == 0 {
                            VStack(spacing: OCSpacing.md) {
                                Text("Run this command on the server’s computer to get a pairing link and QR code.")
                                    .font(OCType.small).foregroundStyle(OCColor.textMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                Button { OCCopy.text("opencode pair"); copiedPairCommand = true } label: {
                                    Text(copiedPairCommand ? "Copied" : "opencode pair").font(OCType.code)
                                }.buttonStyle(OCButtonStyle()).accessibilityLabel("Copy opencode pair")
                                    .accessibilityIdentifier("copyPairCommand")
                            }.padding(.top, OCSpacing.lg)
                        }
                    }.frame(maxWidth: OCLayout.connectionForm)
                        .padding(.horizontal, OCSpacing.xl).padding(.vertical, OCSpacing.xxl)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.background(OCColor.background).textFieldStyle(OCTextFieldStyle(font: OCType.large))
            }
            .disabled(working)
            .ocTheme()
            .ocNavigationTitle(repairing == nil ? "Add server" : "Re-pair server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { task?.cancel(); dismiss() } } }
            .sheet(isPresented: $explainLocal) {
                LocalNetworkExplanation {
                    explainLocal = false
                    task = Task { await registry.acknowledgeLocalNetwork(); await connect() }
                }.uiTestConnectionDiagnostics(registry)
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScannerView(scanned: { value in link = value; scanning = false; connectTapped() },
                                  failed: { scannerError = "The camera is unavailable. Allow Camera access in Settings, or paste your pairing link." })
                        .overlay {
                            if let scannerError { ContentUnavailableView("Camera unavailable", systemImage: "camera", description: Text(scannerError)) }
                        }
                        .ocNavigationTitle("Scan pairing code")
                        .toolbar { Button("Cancel") { scanning = false } }
                }
                .onDisappear { scannerError = nil }
            }
            .onAppear { if let repairing { address = repairing.record.endpoints.first?.url.absoluteString ?? "" } }
            .onDisappear { task?.cancel(); password = ""; link = "" }
            .task(id: connecting?.id) {
                guard let connecting else { return }
                for await state in Observations({ connecting.state }) {
                    guard !Task.isCancelled else { return }
                    finishIfSettled(connecting, state: state)
                    if finished { return }
                }
            }
        }.ocSheet().uiTestConnectionDiagnostics(registry)
    }
    @ViewBuilder private var methodSwitch: some View {
        Text(method == 0 ? "No pairing link?" : "Have a pairing link?").font(OCType.small).foregroundStyle(OCColor.textFaint)
        Button(method == 0 ? "Use password" : "Use pairing link") { method = method == 0 ? 1 : 0; error = nil }
            .buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("connectionMethod")
    }
    private func connectTapped() {
        if registry.needsLocalNetworkExplanation(address: method == 0 ? link : address, pairing: method == 0) {
            explainLocal = true
        } else { task = Task { await connect() } }
    }
    private func connect() async {
        error = nil; working = true
        do {
            let server: ServerStore
            if method == 0 { server = try await registry.pair(link, replacing: repairing) }
            else if let repairing {
                let endpoint = try ServerRegistry.endpoint(address)
                let endpoints = repairing.record.endpoints.contains(where: { $0.url == endpoint.url })
                    ? repairing.record.endpoints : repairing.record.endpoints + [endpoint]
                try await repairing.repair(credential: .password(password), endpoints: endpoints)
                server = repairing
            } else { server = try await registry.addManually(name: name, address: address, password: password) }
            try Task.checkCancellation()
            password = ""; link = ""; connecting = server
            // Fast local servers may finish before SwiftUI installs the state observer.
            finishIfSettled(server, state: server.state)
        } catch is CancellationError { working = false }
        catch { self.error = ServerRegistry.errorMessage(error); working = false }
    }
    private func finishIfSettled(_ server: ServerStore, state: ConnectionState) {
        guard !finished else { return }
        switch state {
        case .connected, .unauthorized, .incompatible, .waiting, .serviceStarting:
            finished = true; working = false; completed(server)
        default: break
        }
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    let failed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(scanned: scanned, failed: failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        context.coordinator.start(scanner)
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        coordinator.startTask?.cancel(); controller.stopScanning()
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let scanned: (String) -> Void
        let failed: () -> Void
        var startTask: Task<Void, Never>?
        var delivered = false
        init(scanned: @escaping (String) -> Void, failed: @escaping () -> Void) { self.scanned = scanned; self.failed = failed }
        deinit { startTask?.cancel() }
        func start(_ scanner: DataScannerViewController) {
            startTask = Task { [weak self, weak scanner] in
                await Task.yield()
                guard !Task.isCancelled, let scanner else { return }
                do { try scanner.startScanning() } catch { self?.failed() }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    delivered = true; dataScanner.stopScanning(); scanned(value); return
                }
            }
        }
    }
}
#endif
