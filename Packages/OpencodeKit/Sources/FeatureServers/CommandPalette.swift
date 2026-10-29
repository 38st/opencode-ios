// Sources: packages/app/src/shell/commands/{dialog.tsx,dialog.css,palette.ts} and runtime/i18n/en.ts (palette.*).
#if os(iOS)
import SwiftUI
import UIKit
import OCModels
import OCDesign

/// The ⌘K switcher: commands, sessions from every paired server and projects, in the desktop's command palette.
struct CommandPalette: View {
    let search: (String) -> [SwitcherGroup]
    /// The entry, and whether to open it in a new window.
    let select: (SwitcherEntry, Bool) -> Void
    let supportsWindows: Bool
    /// The panel's tallest size; nil fills a sheet.
    var maxHeight: CGFloat?
    let close: () -> Void
    @State private var query: String
    @State private var active = 0
    @State private var listHeight: CGFloat = 0
    init(search: @escaping (String) -> [SwitcherGroup], select: @escaping (SwitcherEntry, Bool) -> Void, supportsWindows: Bool,
         maxHeight: CGFloat? = nil, query: String = "", close: @escaping () -> Void) {
        self.search = search; self.select = select; self.supportsWindows = supportsWindows; self.maxHeight = maxHeight
        self.close = close; _query = State(initialValue: query)
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let groups = search(query)
        let entries = groups.flatMap(\.entries)
        let current = Self.wrap(active, entries.count).map { entries[$0].id }
        VStack(spacing: 0) {
            HStack(spacing: OCSpacing.sm) {
                OCIcon("magnifying-glass").foregroundStyle(OCColor.iconMuted)
                // The field keeps the closures of its last update; both read the list as it is when the key arrives.
                PaletteField(text: $query, placeholder: "Search commands and sessions", move: { active += $0 }, submit: { alternate in
                    let entries = search(query).flatMap(\.entries)
                    if let index = Self.wrap(active, entries.count) { select(entries[index], alternate && supportsWindows) }
                }, cancel: close).frame(minHeight: OCLayout.touchTarget)
            }.padding(.horizontal, OCSpacing.md)
                .background(OCColor.layer2.opacity(0.6), in: RoundedRectangle(cornerRadius: OCRadius.md))
                .padding(OCSpacing.sm)
            Rectangle().fill(OCColor.border).frame(height: OCBorder.hairline)
            if entries.isEmpty {
                Text("No results found").font(OCType.small).foregroundStyle(OCColor.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 220).accessibilityIdentifier("paletteEmpty")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groups) { group in
                                Text(group.title).font(OCType.small).foregroundStyle(OCColor.textMuted)
                                    .padding(.horizontal, OCSpacing.md).padding(.top, OCSpacing.md).padding(.bottom, OCSpacing.xs)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.entries) { entry in row(entry, active: entry.id == current) }
                            }
                        }.padding(.horizontal, OCSpacing.sm).padding(.bottom, OCSpacing.sm)
                            // A new query is a new list: the lazy stack otherwise keeps rows that moved up as they looked.
                            .id(query)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    // Desktop height limits; large text takes the room the window has instead.
                    }.frame(height: typeSize.isAccessibilitySize ? nil : maxHeight.map { max(OCLayout.touchTarget, min(max(listHeight, 220), $0 - 60)) })
                        .onChange(of: active) { _, _ in if let current { proxy.scrollTo(current) } }
                }
            }
        }
        .onChange(of: query) { _, _ in active = 0 }
        // A container of its own, so its identifier does not replace the search field's.
        .accessibilityElement(children: .contain).accessibilityIdentifier("commandPalette")
    }
    /// The active row, wrapping both ways as the desktop's list does.
    static func wrap(_ active: Int, _ count: Int) -> Int? { count > 0 ? (active % count + count) % count : nil }
    private func row(_ entry: SwitcherEntry, active: Bool) -> some View {
        // At accessibility sizes text wraps and the key moves under the title, as elsewhere in the app.
        let large = typeSize.isAccessibilitySize
        return Button { select(entry, false) } label: {
            HStack(alignment: large ? .top : .center, spacing: OCSpacing.sm) {
                OCIcon(icon(entry)).foregroundStyle(OCColor.iconMuted)
                VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                    Text(entry.title).font(OCType.small).foregroundStyle(OCColor.text).lineLimit(large ? nil : 1)
                    if !entry.detail.isEmpty { Text(entry.detail).font(OCType.micro).foregroundStyle(OCColor.textMuted).lineLimit(large ? nil : 1) }
                    if large, let shortcut = entry.shortcut { chip(shortcut) }
                }
                Spacer(minLength: 0)
                if !large, let shortcut = entry.shortcut { chip(shortcut) }
            }.padding(.horizontal, OCSpacing.sm).padding(.vertical, large ? OCSpacing.xs : 0).frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
                .background(active ? OCColor.hover : .clear, in: RoundedRectangle(cornerRadius: OCRadius.md))
        }.buttonStyle(.plain).ocHover().id(entry.id)
            .accessibilityIdentifier("palette-" + entry.id)
            .accessibilityAddTraits(active ? .isSelected : [])
            .contextMenu {
                if case .session = entry.kind {
                    Button("Open") { select(entry, false) }
                    if supportsWindows { Button("Open in New Window") { select(entry, true) } }
                }
            }
    }
    private func chip(_ shortcut: String) -> some View {
        Text(shortcut).font(OCType.micro).foregroundStyle(OCColor.textMuted)
            .padding(.horizontal, OCSpacing.xs).padding(.vertical, OCSpacing.xxs)
            .background(OCColor.layer2, in: RoundedRectangle(cornerRadius: OCRadius.sm))
            .accessibilityLabel("Shortcut " + shortcut)
    }
    private func icon(_ entry: SwitcherEntry) -> String {
        switch entry.kind {
        case .command: "console"
        case .session: "bubble-5"
        case .project: "folder"
        case .settings(let value): ServerSettingsSection(rawValue: String(value.split(separator: ":").last ?? "")).map(\.icon) ?? "settings-gear"
        }
    }
}

/// A search field that keeps ↑, ↓, ⌥↩ and ⎋ while it has focus; Return opens the active entry.
struct PaletteField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let move: (Int) -> Void
    let submit: (Bool) -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PaletteTextField {
        OCFonts.register()
        let field = PaletteTextField()
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: "Inter-Regular", size: 14) ?? .preferredFont(forTextStyle: .body))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(OCColor.text); field.tintColor = UIColor(OCColor.accent)
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(OCColor.textFaint)])
        field.autocorrectionType = .no; field.autocapitalizationType = .none; field.spellCheckingType = .no
        field.returnKeyType = .go; field.clearButtonMode = .whileEditing
        field.accessibilityLabel = placeholder; field.accessibilityIdentifier = "paletteSearch"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: PaletteTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.move = move; field.submit = submit; field.cancel = cancel
    }
    /// One line: as wide as offered, as tall as the text.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PaletteTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: max(OCLayout.touchTarget, uiView.intrinsicContentSize.height))
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PaletteField
        init(_ parent: PaletteField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.submit(false); return false }
    }
}
final class PaletteTextField: UITextField {
    var move: (Int) -> Void = { _ in }
    var submit: (Bool) -> Void = { _ in }
    var cancel: () -> Void = {}
    private var focusTask: Task<Void, Never>?
    deinit { focusTask?.cancel() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        focusTask?.cancel()
        guard window != nil else { return }
        // The palette opens ready to type; focus after the presenting update finishes.
        focusTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.window != nil else { return }
            self.becomeFirstResponder()
        }
    }
    override var keyCommands: [UIKeyCommand]? {
        guard markedTextRange == nil else { return super.keyCommands }
        // Return itself reaches the delegate's textFieldShouldReturn.
        let keys: [(KeyChord, Selector)] = [(WorkspaceKeys.Palette.up, #selector(up)), (WorkspaceKeys.Palette.down, #selector(down)),
                                            (WorkspaceKeys.Palette.openInNewWindow, #selector(alternate)), (WorkspaceKeys.Palette.cancel, #selector(dismiss))]
        return keys.map { $0.0.keyCommand($0.1) } + (super.keyCommands ?? [])
    }
    @objc private func up() { move(-1) }
    @objc private func down() { move(1) }
    @objc private func alternate() { submit(true) }
    @objc private func dismiss() { cancel() }
}
#endif
