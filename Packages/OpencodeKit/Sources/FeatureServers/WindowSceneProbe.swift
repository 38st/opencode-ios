#if os(iOS)
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import OCModels

/// The UIKit side of a window: its scene session, to bring the window forward, the touches that put it in use, and
/// the scene's disconnection, which SwiftUI does not always report as the window's views disappearing.
struct WindowSceneProbe: UIViewRepresentable {
    let attached: (UISceneSession) -> Void
    let touched: () -> Void
    let disconnected: () -> Void
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) { view.attached = attached; view.touched = touched; view.disconnected = disconnected }
    final class ProbeView: UIView {
        var attached: (UISceneSession) -> Void = { _ in }
        var touched: () -> Void = {}
        var disconnected: () -> Void = {}
        /// Both are removed whenever the view leaves its window, which it does before it goes away.
        private var observer: TouchObserver?
        private var disconnection: (any NSObjectProtocol)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let observer { observer.view?.removeGestureRecognizer(observer); self.observer = nil }
            if let disconnection { NotificationCenter.default.removeObserver(disconnection); self.disconnection = nil }
            guard let window, let scene = window.windowScene else { return }
            attached(scene.session)
            let observer = TouchObserver { [weak self] in self?.touched() }
            window.addGestureRecognizer(observer)
            self.observer = observer
            disconnection = NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.disconnected() }
            }
        }
    }
    /// Sees every touch that starts in its window and fails at once, so it never takes part in recognition.
    final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private let began: () -> Void
        init(_ began: @escaping () -> Void) {
            self.began = began
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
            delegate = self
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            began()
            state = .failed
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

enum WindowScenes {
    /// Brings a window forward; iPadOS decides how, in its current multitasking mode. `failed` runs if iPadOS refuses.
    static func activate(_ session: UISceneSession?, failed: (@MainActor @Sendable () -> Void)? = nil) {
        guard let session else { return }
        // UIKit may call this off the main thread, so the closure is not the main actor's.
        UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(session: session)) { @Sendable _ in
            guard let failed else { return }
            Task { @MainActor in failed() }
        }
    }
    static func close(_ session: UISceneSession) {
        // UIKit may call this off the main thread, so the closure is not the main actor's.
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { @Sendable error in
            #if DEBUG
            let description = error.localizedDescription
            Task { @MainActor in closeErrors.append(description) }
            #endif
        }
    }
    #if DEBUG
    /// Why iPadOS refused to close a window, for the UI-test inventory.
    @MainActor static var closeErrors: [String] = []
    #endif
    /// Closes every window but this one.
    static func closeOthers(keeping session: UISceneSession?) {
        for other in UIApplication.shared.openSessions where other != session { close(other) }
    }
    private static let rootKey = "workspace.session"
    /// Records the window's root session with its scene session, which iPadOS keeps across launches, so a window
    /// that is not connected (in the app switcher, or not yet restored) can still be found and brought forward.
    static func mark(_ session: UISceneSession?, root: SessionRef?) {
        guard let session else { return }
        var info = session.userInfo ?? [:]
        info[rootKey] = root?.id
        session.userInfo = info
    }
    static func session(showing root: SessionRef, except current: UISceneSession?) -> UISceneSession? {
        UIApplication.shared.openSessions.first { $0 != current && $0.userInfo?[rootKey] as? String == root.id }
    }
    /// Every window iPadOS keeps for the app, connected or not, with its root session.
    static var inventory: String {
        var lines = UIApplication.shared.openSessions.map { "scene connected=\($0.scene != nil) root=" + (($0.userInfo?[rootKey] as? String)?.split(separator: ":").last.map(String.init) ?? "") }.sorted()
        #if DEBUG
        lines += closeErrors.map { "close-error " + $0 }
        #endif
        return lines.joined(separator: "\n")
    }
}
#endif
