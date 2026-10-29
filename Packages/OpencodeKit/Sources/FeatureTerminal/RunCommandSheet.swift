// "Run a command" outside any session: the desktop runs commands through the same shell service and stops them from its
// running list (packages/app/src/session/composer/region.tsx at v2.2.0).
#if os(iOS)
import SwiftUI
import OCFoundation
import OCModels
import OCSync
import OCDesign

public struct RunCommandSheet: View {
    let model: ShellRunModel
    @AppStorage(TerminalSettings.fontSizeKey) private var fontSize = TerminalSettings.defaultFontSize
    @State private var command = ""
    @State private var engine: SwiftTermEngine?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(model: ShellRunModel) { self.model = model }
    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OCSpacing.md) {
                HStack(spacing: OCSpacing.sm) {
                    TextField("Command", text: $command).font(OCType.code).textFieldStyle(OCTextFieldStyle(font: OCType.code))
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go).onSubmit(run)
                        .accessibilityIdentifier("runCommandField")
                    Button("Run", action: run).buttonStyle(OCButtonStyle(.contrast))
                        .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("runCommandRun")
                }
                Text("Runs in \(model.directory) on the server, outside any session.").font(OCType.micro).foregroundStyle(OCColor.textMuted)
                if let shell = model.shell { status(shell) }
                if let error = model.error { OCBanner(error, tone: .danger) }
                Group {
                    if let engine { TerminalEngineView(engine: engine, focused: false) } else { Color.clear }
                }.frame(minHeight: 160, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: OCRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
                if !model.running.isEmpty { runningList }
            }.padding(OCSpacing.md)
                .background(OCColor.background)
                .navigationTitle("Run a command").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("runCommandDone") } }
        }
        .onAppear {
            model.appear()
            let engine = engine ?? SwiftTermEngine(session: nil, fontSize: fontSize, optionAsMeta: false, readOnly: true)
            self.engine = engine
            model.attach(engine)
        }
    }
    /// The field empties for the next command, as a shell prompt does.
    private func run() {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.run(command); command = ""
    }
    /// The command, then how it is doing: on one line, or stacked at the accessibility sizes.
    private func status(_ shell: ShellInfo) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.xs)) : AnyLayout(HStackLayout(spacing: OCSpacing.sm))
        return layout {
            Text(shell.command).font(OCType.code).lineLimit(stacked ? 3 : 1).truncationMode(.middle)
            if !stacked { Spacer(minLength: 0) }
            HStack(spacing: OCSpacing.sm) {
                if model.isRunning {
                    OCSpinner("Running").accessibilityIdentifier("runCommandRunning")
                    Button("Stop") { model.stop() }.buttonStyle(OCButtonStyle(.danger)).disabled(model.stopping).accessibilityIdentifier("runCommandStop")
                } else {
                    OCPill(Self.ended(shell), tone: shell.exit.map { $0 == 0 } ?? false ? .neutral : .warning)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("runCommandEnded")
                }
            }
        }
    }
    private var runningList: some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            OCSidebarHeader("Running commands")
            ForEach(model.running) { shell in
                Button { model.show(shell) } label: {
                    HStack {
                        Text(shell.command).font(OCType.code).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if shell.metadata?["sessionID"]?.stringValue != nil { OCBadge("Agent") }
                    }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).hoverEffect(.highlight).accessibilityIdentifier("runningShell-" + shell.id)
            }
        }
    }
    static func ended(_ shell: ShellInfo) -> String {
        switch shell.status {
        case "killed": "Stopped"
        case "timeout": "Timed out"
        default: shell.exit.map { "Exited with code \(Int($0))" } ?? "Finished"
        }
    }
}
#endif
