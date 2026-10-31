import Foundation

/// One-tap git actions. Each is a prompt to the session's agent, which runs git with its own permissions; the app
/// never runs git itself. The desktop app has no such actions (v2.2.2), so the wording is this app's.
public enum GitQuickAction: String, CaseIterable, Identifiable, Sendable {
    case commitAndPush, openPullRequest
    public var id: String { rawValue }
    public var title: String {
        switch self { case .commitAndPush: localized("Commit and push"); case .openPullRequest: localized("Open a pull request") }
    }
    public var confirmTitle: String {
        switch self { case .commitAndPush: localized("Send commit prompt"); case .openPullRequest: localized("Send pull request prompt") }
    }
    public var message: String {
        switch self {
        case .commitAndPush: localized("The agent will commit the current changes and push the branch, after its current turn if it is working. It sends this prompt:")
        case .openPullRequest: localized("The agent will push the branch and open a pull request, after its current turn if it is working. It sends this prompt:")
        }
    }
    public var prompt: String {
        switch self {
        case .commitAndPush:
            "Commit all current changes in this repository with a concise commit message that describes them, then push " +
                "the current branch to its remote. If there is nothing to commit, say so and stop."
        case .openPullRequest:
            "Open a pull request for the current branch. Push the branch first if it is not on the remote, write the title " +
                "and description from the changes, and reply with the pull request link. Do not merge it."
        }
    }
}
