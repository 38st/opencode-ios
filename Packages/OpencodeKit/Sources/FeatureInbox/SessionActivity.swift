#if os(iOS)
import Foundation
import OCModels
import OCShared

/// A session as a user activity: dropping a dragged Home row at the edge of the screen opens it in a new window.
public enum SessionActivity {
    /// Declared in the app's `NSUserActivityTypes`.
    public static var type: String { (Bundle.main.bundleIdentifier ?? "app.opencode.client") + ".session" }
    public static func activity(_ ref: SessionRef) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.title = "Session"
        if let url = DeepLink.url(serverID: ref.serverID.rawValue, sessionID: ref.sessionID) {
            activity.userInfo = ["url": url.absoluteString]; activity.targetContentIdentifier = url.absoluteString
        }
        return activity
    }
    public static func provider(_ ref: SessionRef) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerObject(activity(ref), visibility: .all)
        return provider
    }
    /// The session link an activity carries.
    public static func url(_ activity: NSUserActivity) -> URL? { (activity.userInfo?["url"] as? String).flatMap(URL.init(string:)) }
}
#endif
