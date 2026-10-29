// SwiftTerm 1.99.1 as the app's terminal renderer. Output is parsed on the main actor as it arrives, so a snapshot
// always matches the session's cursor. The Core Graphics renderer is used; Metal is never enabled.
#if os(iOS)
import SwiftUI
import UIKit
import GameController
import SwiftTerm
import OCModels
import OCSync
import OCDesign

/// SwiftTerm's view with the app's key bar and sticky modifiers.
class OCTerminalView: TerminalView {
    weak var session: TerminalSession?
    var keyBarAllowed = true { didSet { updateAccessory() } }
    private lazy var keyBar = KeyBarInputView(terminal: self)
    private var observing = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if !observing {
            observing = true
            for name in [NSNotification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
                NotificationCenter.default.addObserver(self, selector: #selector(keyboardsChanged), name: name, object: nil)
            }
        }
        updateAccessory()
    }
    @objc nonisolated private func keyboardsChanged() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.updateAccessory() } }
    }
    /// The key bar shows on iPhone, and on iPad without a hardware keyboard.
    func updateAccessory() {
        let hardware = UIDevice.current.userInterfaceIdiom == .pad && GCKeyboard.coalesced != nil
        let accessory: UIView? = keyBarAllowed && !hardware ? keyBar : nil
        guard inputAccessoryView !== accessory else { return }
        inputAccessoryView = accessory
        if isFirstResponder { reloadInputViews() }
    }
    /// SwiftTerm toggles Option as Meta on ⌥⌘O; the setting belongs to Settings, so here the chord does nothing.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.modifierFlags.isSuperset(of: [.alternate, .command]) == true && $0.key?.charactersIgnoringModifiers == "o" }) { return }
        super.pressesBegan(presses, with: event)
    }
    /// Text typed while Ctrl or Alt is latched on the key bar goes through the latch.
    override func insertText(_ text: String) {
        if let session, !session.latch.latched.isEmpty { session.type(text); return }
        super.insertText(text)
    }
    /// The cursor takes the shape a program asks for and never blinks: SwiftTerm blinks it with an endless animation.
    nonisolated override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        super.cursorStyleChanged(source: source, newStyle: newStyle.steady)
    }
}

extension CursorStyle {
    nonisolated var steady: CursorStyle {
        switch self {
        case .blinkBlock, .steadyBlock: .steadyBlock
        case .blinkBar, .steadyBar: .steadyBar
        case .blinkUnderline, .steadyUnderline: .steadyUnderline
        }
    }
}

@MainActor final class SwiftTermEngine: NSObject, TerminalEngine, TerminalViewDelegate {
    let view: OCTerminalView
    let readOnly: Bool
    private weak var session: TerminalSession?
    private var cols = 0, rows = 0
    private var restoring = false
    /// Replies SwiftTerm makes to queries (DA, CPR) in replayed or restored output: it sends them on a later main-queue
    /// turn, so they are dropped until a turn queued after that output has run.
    private var muted = 0
    /// Where the terminal's own bytes go: the session.
    lazy var forward: ([UInt8]) -> Void = { [weak self] bytes in self?.session?.send(bytes) }
    private var traits: (any UITraitChangeRegistration)?

    init(session: TerminalSession?, fontSize: Double, optionAsMeta: Bool, readOnly: Bool = false) {
        var options = TerminalOptions.default
        options.scrollback = 10_000
        options.cursorStyle = .steadyBlock
        view = readOnly ? ReadOnlyTerminalView(frame: .zero, font: Self.font(fontSize), options: options)
            : OCTerminalView(frame: .zero, font: Self.font(fontSize), options: options)
        self.readOnly = readOnly
        self.session = session
        super.init()
        view.session = session
        view.terminalDelegate = self
        view.optionAsMetaKey = optionAsMeta
        view.keyBarAllowed = !readOnly
        // Keeps the default ANSI colours readable on the light background.
        view.minimumContrastRatio = 3
        view.accessibilityIdentifier = readOnly ? "shellOutput" : "terminal"
        applyColors()
        traits = view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: OCTerminalView, _: UITraitCollection) in
            self?.applyColors()
        }
        if readOnly { view.feed(text: Self.hiddenCursor) }
        let dimensions = view.terminalInputStateSnapshot()?.dimensions
        cols = dimensions?.cols ?? 0; rows = dimensions?.rows ?? 0
    }

    static func font(_ size: Double) -> UIFont {
        OCFonts.register()
        let size = CGFloat(min(max(size, TerminalSettings.fontSizes.lowerBound), TerminalSettings.fontSizes.upperBound))
        return UIFont(name: "JetBrainsMonoNFM-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    /// The background is the layer's colour and is not refreshed on an appearance change, so every colour is resolved
    /// for the view's current traits. `backgroundColor` stays unset: UIKit would replace that layer colour, and cells
    /// SwiftTerm clears would show black.
    func applyColors() {
        let traits = view.traitCollection, dark = traits.userInterfaceStyle == .dark
        let foreground = UIColor(OCColor.text).resolvedColor(with: traits), background = UIColor(OCColor.background).resolvedColor(with: traits)
        view.nativeForegroundColor = foreground
        view.nativeBackgroundColor = background
        view.caretColor = foreground
        view.selectedTextBackgroundColor = foreground.withAlphaComponent(dark ? 0.25 : 0.2)
    }
    /// A Settings change. Setting the font resizes the terminal, which soft-resets its modes, so the modes a program
    /// set are fed back locally afterwards.
    func update(fontSize: Double, optionAsMeta: Bool) {
        view.optionAsMetaKey = optionAsMeta
        let font = Self.font(fontSize)
        guard view.font.pointSize != font.pointSize, let state = view.terminalInputStateSnapshot() else { return }
        view.font = font
        view.feed(text: TerminalSerializer.modes(state))
    }

    // MARK: TerminalEngine

    func feed(_ text: String) { view.feed(text: text) }
    func replay(_ text: String) { mute { view.feed(text: text) } }
    private func mute(_ work: () -> Void) {
        muted += 1
        work()
        DispatchQueue.main.async { [weak self] in self?.muted -= 1 }
    }
    func reset() { view.feed(text: "\u{1B}c\u{1B}[3J" + (readOnly ? Self.hiddenCursor : "")) }
    /// Output nobody types into shows no cursor.
    private static let hiddenCursor = "\u{1B}[?25l"
    func snapshot(scrollback: Int) -> String? {
        guard let state = view.terminalInputStateSnapshot(),
              let normal = view.terminalContentSnapshot(region: .history(maximumScrollbackRows: scrollback), buffer: .normal) else { return nil }
        let alternate = state.isAlternateBuffer ? view.terminalContentSnapshot(region: .history(maximumScrollbackRows: 0), buffer: .alt) : nil
        return TerminalSerializer.serialize(normal: normal, alternate: alternate, state: state)
    }
    /// Replays a saved screen at the size it was saved at; the next layout resizes it to the view.
    func restore(_ screen: String, cols: Int, rows: Int) {
        restoring = true
        defer { restoring = false; view.setNeedsLayout() }
        if cols > 0, rows > 0, (cols, rows) != (self.cols, self.rows) { view.resize(cols: cols, rows: rows) }
        mute { view.feed(text: screen) }
    }
    var size: (cols: Int, rows: Int) { (cols, rows) }
    var applicationCursor: Bool { view.terminalInputStateSnapshot()?.applicationCursor ?? false }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        cols = newCols; rows = newRows
        if !restoring { session?.resized(cols: newCols, rows: newRows) }
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { if !readOnly && !restoring && muted == 0 { forward(Array(data)) } }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    /// Only a tap reaches here, and only web links open.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        UIApplication.shared.open(url)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    /// A program may not read or set the pasteboard (OSC 52).
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
}

/// The Run a command sheet's output: selectable, never focused, so no keyboard appears.
final class ReadOnlyTerminalView: OCTerminalView {
    override var canBecomeFirstResponder: Bool { false }
}

/// The renderers of recently shown terminals, so returning to one shows it at once. Each keeps its session's socket
/// open while the app is active; the least recently shown one past the limit saves, disconnects and is released.
@MainActor final class TerminalEngines {
    static let shared = TerminalEngines()
    static let limit = 4
    private var engines: [ObjectIdentifier: (session: TerminalSession, engine: SwiftTermEngine)] = [:]
    private var order: [ObjectIdentifier] = []
    private var attaching: [ObjectIdentifier: Task<Void, Never>] = [:]

    func engine(for session: TerminalSession, fontSize: Double, optionAsMeta: Bool) -> SwiftTermEngine {
        let key = ObjectIdentifier(session)
        order.removeAll { $0 == key }; order.append(key)
        if let entry = engines[key] { entry.engine.update(fontSize: fontSize, optionAsMeta: optionAsMeta); return entry.engine }
        let engine = SwiftTermEngine(session: session, fontSize: fontSize, optionAsMeta: optionAsMeta)
        engines[key] = (session, engine)
        attaching[key] = Task { [weak self] in
            await session.attach(engine)
            self?.attaching.removeValue(forKey: key)
        }
        while order.count > Self.limit { release(order.removeFirst()) }
        return engine
    }
    func drop(_ session: TerminalSession) {
        let key = ObjectIdentifier(session)
        order.removeAll { $0 == key }
        release(key)
    }
    private func release(_ key: ObjectIdentifier) {
        attaching.removeValue(forKey: key)?.cancel()
        guard let entry = engines.removeValue(forKey: key) else { return }
        entry.session.detach()
        entry.engine.view.removeFromSuperview()
        // SwiftTerm must hear when a view is closed for good; without Metal it finishes at once.
        entry.engine.view.updateUiClosed()
    }
}

/// A terminal's renderer in SwiftUI. The renderer outlives this view, so it moves between windows and tabs intact.
struct TerminalEngineView: UIViewRepresentable {
    let engine: SwiftTermEngine
    var focused: Bool

    func makeUIView(context: Context) -> TerminalContainer { TerminalContainer() }
    func updateUIView(_ container: TerminalContainer, context: Context) {
        container.focusOnShow = focused && !engine.readOnly
        container.host(engine)
    }
    static func dismantleUIView(_ container: TerminalContainer, coordinator: ()) { container.release() }
}

final class TerminalContainer: UIView {
    private weak var engine: SwiftTermEngine?
    /// Take the keyboard once, when the terminal first shows here; later updates leave focus where the user put it.
    var focusOnShow = false
    private var tookFocus = false
    override func didMoveToWindow() { super.didMoveToWindow(); focusIfNeeded() }
    private func focusIfNeeded() {
        guard focusOnShow, !tookFocus, window != nil, let view = engine?.view, view.superview === self else { return }
        tookFocus = view.becomeFirstResponder()
    }
    func host(_ engine: SwiftTermEngine) {
        defer { focusIfNeeded() }
        guard self.engine !== engine || engine.view.superview !== self else { return }
        self.engine = engine; tookFocus = false
        engine.view.removeFromSuperview()
        engine.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(engine.view)
        NSLayoutConstraint.activate([
            engine.view.leadingAnchor.constraint(equalTo: leadingAnchor), engine.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            engine.view.topAnchor.constraint(equalTo: topAnchor), engine.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        #if DEBUG
        TerminalProbes.install(in: self, engine: engine)
        #endif
    }
    func release() { if let view = engine?.view, view.superview === self { view.removeFromSuperview() } }
}
#endif
