#if DEBUG && os(iOS)
import Foundation
import OCAppIntents
import OCIntents
import OCShared

/// UI tests only: runs an intent's own `perform()` in the app process with the values a Shortcuts run would pass.
/// It stands in for the system's dispatch, which an app without a team identifier does not get on the simulator
/// (linkd rejects it), so Shortcuts' parameter prompts, the dispatch into this process and the authentication policy
/// are bypassed; everything `perform()` does is not.
///
/// `opencodeios://debug-intent/send?server=<id>&session=<id>&text=<prompt>`
/// `opencodeios://debug-intent/status?server=<id>&session=<id>`
@MainActor public enum DebugIntentHook {
    /// True when the link was the hook's, whether or not it ran.
    public static func handle(_ url: URL) -> Bool {
        guard url.scheme == "opencodeios", url.host == "debug-intent" else { return false }
        guard ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"]?.hasPrefix("ui-") == true,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return true }
        let value = { (name: String) in items.first { $0.name == name }?.value ?? "" }
        let id = value("server") + ":" + value("session")
        Task {
            do {
                guard let session = try await SessionQuery().entities(for: [id]).first else { throw IntentError.sessionNotFound }
                switch url.lastPathComponent {
                case "send":
                    let intent = SendPromptIntent()
                    intent.destination = .session; intent.session = session; intent.prompt = value("text")
                    _ = try await intent.perform()
                case "status":
                    _ = try await GetSessionStatusIntent(session: session).perform()
                default: break
                }
            } catch {
                try? SystemSnapshotStore.appGroup().recordIntent("debug-intent error=\(error)")
            }
        }
        return true
    }
}
#endif
