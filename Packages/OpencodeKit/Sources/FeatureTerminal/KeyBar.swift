#if os(iOS)
import SwiftUI
import UIKit
import SwiftTerm
import OCModels
import OCSync
import OCDesign

/// The keys a touch keyboard lacks: Esc, sticky Ctrl and Alt, Tab, the arrows and | ~ / -, scrolling when they do not
/// fit. Ctrl and Alt latch for the next key from the bar or either keyboard; a second tap releases them.
public struct KeyBarView: View {
    let session: TerminalSession
    public init(session: TerminalSession) { self.session = session }
    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OCSpacing.xs) {
                key("esc", label: "Escape") { session.press(.escape) }
                latch("ctrl", label: "Control", .control)
                latch("alt", label: "Option", .alt)
                ForEach(Array(TerminalKeys.bar.enumerated()), id: \.offset) { _, item in
                    key(title(item), label: label(item)) { session.press(item) }
                }
            }.padding(.horizontal, OCSpacing.sm).padding(.vertical, OCSpacing.xs)
        }.scrollIndicators(.hidden)
            .background(OCColor.layer2)
            .overlay(alignment: .top) { Rectangle().fill(OCColor.border).frame(height: OCBorder.hairline) }
            .accessibilityElement(children: .contain).accessibilityLabel("Terminal keys").accessibilityIdentifier("terminalKeyBar")
    }
    private func key(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { cap(title, latched: false) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier("terminalKey-" + label)
    }
    private func latch(_ title: String, label: String, _ modifier: TerminalModifiers) -> some View {
        let latched = session.latch.latched.contains(modifier)
        return Button { session.toggle(modifier) } label: { cap(title, latched: latched) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(latched ? .isSelected : [])
            .accessibilityValue(latched ? "Latched for the next key" : "Off").accessibilityIdentifier("terminalKey-" + label)
    }
    private func cap(_ title: String, latched: Bool) -> some View {
        Text(title).font(OCType.code).foregroundStyle(latched ? OCColor.textInverse : OCColor.text)
            .frame(minWidth: OCLayout.touchTarget, minHeight: OCLayout.touchTarget)
            .background(latched ? OCColor.contrast : OCColor.surface, in: RoundedRectangle(cornerRadius: OCRadius.sm))
            .contentShape(Rectangle())
    }
    private func title(_ key: TerminalKey) -> String {
        switch key {
        case .escape: "esc"
        case .tab: "tab"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .text(let text): text
        }
    }
    private func label(_ key: TerminalKey) -> String {
        switch key {
        case .escape: "Escape"
        case .tab: "Tab"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .left: "Left arrow"
        case .right: "Right arrow"
        case .text("|"): "Vertical bar"
        case .text("~"): "Tilde"
        case .text("/"): "Slash"
        case .text("-"): "Hyphen"
        case .text(let text): text
        }
    }
}

/// The key bar as the terminal's input accessory, above the software keyboard.
final class KeyBarInputView: UIInputView {
    private let host: UIHostingController<AnyView>
    init(terminal: OCTerminalView) {
        // The bar grows with the text size up to a point, so it never covers the terminal.
        host = UIHostingController(rootView: AnyView(terminal.session.map { AnyView(KeyBarView(session: $0).dynamicTypeSize(...DynamicTypeSize.accessibility2).ocTheme()) } ?? AnyView(EmptyView())))
        host.sizingOptions = .intrinsicContentSize
        // The accessory sits above the keyboard; the window's safe area would only make the bar taller than its keys.
        host.safeAreaRegions = []
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 52), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor), host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor), host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: host.view.intrinsicContentSize.height) }
}

#if DEBUG
/// UI tests read the terminal through these, and only under a `ui-` test identity: the visible rows, the size sent to
/// the server, and the `OCSEQ-<n>` marker lines in the whole buffer, in order. Nothing else leaves the terminal.
@MainActor enum TerminalProbes {
    static func install(in container: UIView, engine: SwiftTermEngine) {
        guard ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"]?.hasPrefix("ui-") == true else { return }
        for probe in container.subviews where probe is Probe { probe.removeFromSuperview() }
        let view = engine.view
        let values: [(String, () -> String)] = [
            (engine.readOnly ? "shellOutputScreen" : "terminalScreen", { screen(view) }),
            ("terminalSize", { "\(engine.size.cols)x\(engine.size.rows)" }),
            ("terminalSequence", { sequence(view) }),
        ]
        for (identifier, value) in values where !engine.readOnly || identifier == "shellOutputScreen" {
            let probe = Probe(value: value)
            probe.accessibilityIdentifier = identifier
            probe.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            container.addSubview(probe)
        }
    }
    final class Probe: UIView {
        private let value: () -> String
        init(value: @escaping () -> String) { self.value = value; super.init(frame: .zero); isAccessibilityElement = true }
        required init?(coder: NSCoder) { nil }
        override var accessibilityValue: String? { get { value() } set {} }
    }
    /// The visible rows, with a soft-wrapped row joined to the row it continues.
    static func screen(_ view: OCTerminalView) -> String {
        let rows = view.terminalContentSnapshot(region: .viewport)?.rows ?? []
        return rows.enumerated().map { index, row in (index > 0 && !row.isWrapped ? "\n" : "") + row.text }.joined()
    }
    /// first, last, count, how many numbers between them are missing, how many repeat, and whether they only rise.
    static func sequence(_ view: OCTerminalView) -> String {
        let rows = view.terminalContentSnapshot(region: .history(maximumScrollbackRows: 100_000), buffer: .normal)?.rows ?? []
        let numbers = rows.flatMap { row in row.text.matches(of: /OCSEQ-(\d+)/).compactMap { Int($0.1) } }
        guard let first = numbers.first, let last = numbers.last else { return "count=0" }
        let unique = Set(numbers)
        let missing = max(0, (unique.max() ?? 0) - (unique.min() ?? 0) + 1 - unique.count)
        let rising = zip(numbers, numbers.dropFirst()).allSatisfy { $0 < $1 }
        return "first=\(first) last=\(last) count=\(numbers.count) missing=\(missing) duplicates=\(numbers.count - unique.count) rising=\(rising)"
    }
}
#endif
#endif
