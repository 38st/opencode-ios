// The PTY WebSocket (packages/server/src/handlers/pty.ts, core/src/pty/protocol.ts at v2.2.0): replay and live output
// as text frames, one binary 0x00 frame with the cursor after the replay, input as text frames, close 1000 or 4404.
// The upgrade carries the Basic header, which the server accepts like any request, so no ticket is needed.
import Foundation
import Synchronization
import OCFoundation
import OCModels

public enum PTYFrame: Equatable, Sendable {
    /// Terminal output. The cursor advances by its `utf16.count`, the server's JavaScript string length.
    case output(String)
    /// The absolute cursor after the replay.
    case control(cursor: Int)
    /// A binary frame that is not a control frame, ignored as the reference client ignores it.
    case ignored

    public static func parse(binary data: Data) -> PTYFrame {
        guard data.first == 0x00, let json = try? JSONDecoder().decode(JSONValue.self, from: Data(data.dropFirst())),
              case .integer(let value) = json["cursor"] ?? .null, value >= 0, value <= 9_007_199_254_740_991 else { return .ignored }
        return .control(cursor: Int(value))
    }
}

public enum PTYEvent: Equatable, Sendable {
    case opened
    case frame(PTYFrame)
    /// The socket ended: its close `code` (nil when it failed without a close frame), or the status of a failed upgrade.
    case closed(code: Int?, reason: String?, httpStatus: Int?)
}

/// One socket. Events arrive in order and end with one `.closed`.
public protocol WebSocketConnection: AnyObject, Sendable {
    var events: AsyncStream<PTYEvent> { get }
    func send(_ text: String) async throws
    func close()
}
public protocol WebSocketConnecting: Sendable {
    func open(_ request: URLRequest) -> any WebSocketConnection
}

extension APIClient {
    /// The upgrade request for `path`: a ws or wss URL with the location and `query`, and the Basic header unless a
    /// ticket in `query` authenticates it. The URL never carries the credential.
    public nonisolated func webSocketRequest(path: String, query: [URLQueryItem], scope: Scope, authenticated: Bool = true) throws -> URLRequest {
        var request = try Self.request(baseURL: baseURL, path: path, query: query, scope: scope,
                                       credential: authenticated ? credential : nil, headers: headers)
        guard let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.refused(.invalidURL) }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        request.url = parts.url
        request.setValue(nil, forHTTPHeaderField: "Accept")
        return request
    }
}

/// URLSessionWebSocketTask with redirects refused, 4 MiB messages (replay frames hold 64 Ki UTF-16 units) and a ping
/// every 20 seconds whose pong must arrive within 10, so a dead network path ends the socket.
public struct URLSessionWebSockets: WebSocketConnecting {
    public init() {}
    public func open(_ request: URLRequest) -> any WebSocketConnection { URLSessionWebSocket(request: request) }
}

final class URLSessionWebSocket: NSObject, WebSocketConnection, URLSessionWebSocketDelegate, @unchecked Sendable {
    let events: AsyncStream<PTYEvent>
    private let continuation: AsyncStream<PTYEvent>.Continuation
    /// The one-time end and the ping task, shared by URLSession's delegate queue and the owner's calls.
    private let state = Mutex<(finished: Bool, pinger: Task<Void, Never>?)>((false, nil))
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    init(request: URLRequest) {
        (events, continuation) = AsyncStream.makeStream(of: PTYEvent.self)
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 4 << 20
        self.session = session; self.task = task
        task.resume()
        receive(task)
    }
    deinit { state.withLock { $0.pinger?.cancel() } }

    func send(_ text: String) async throws {
        guard let task else { throw URLError(.cancelled) }
        try await task.send(.string(text))
    }
    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        finish(code: 1000, reason: nil, status: nil)
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)): self.continuation.yield(.frame(.output(text))); self.receive(task)
            case .success(.data(let data)): self.continuation.yield(.frame(PTYFrame.parse(binary: data))); self.receive(task)
            case .success: self.receive(task)
            case .failure: self.ended(task)
            }
        }
    }
    private func ended(_ task: URLSessionWebSocketTask) {
        let code = task.closeCode.rawValue
        let status = (task.response as? HTTPURLResponse)?.statusCode
        finish(code: code == 0 ? nil : code, reason: task.closeReason.map { String(decoding: $0, as: UTF8.self) },
               status: status == 101 ? nil : status)
    }
    private func finish(code: Int?, reason: String?, status: Int?) {
        let first = state.withLock { value in
            defer { value.finished = true; value.pinger?.cancel(); value.pinger = nil }
            return !value.finished
        }
        guard first else { return }
        continuation.yield(.closed(code: code, reason: reason, httpStatus: status))
        continuation.finish()
        // The session keeps its delegate until it is invalidated.
        session?.invalidateAndCancel()
    }
    private func ping() async -> Bool {
        guard let task else { return false }
        return await Self.answers(within: .seconds(10)) { pong in task.sendPing { pong($0) } }
    }
    /// Whether the pong comes back within `timeout`. The answer is given once: a ping on a silently dead path never
    /// calls back, so the deadline answers instead of waiting on it.
    static func answers(within timeout: Duration, sendPing: @escaping @Sendable (@escaping @Sendable ((any Error)?) -> Void) -> Void) async -> Bool {
        let once = Once()
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let answer: @Sendable (Bool) -> Void = { value in if once.first() { done.resume(returning: value) } }
            let deadline = Task { try? await Task.sleep(for: timeout); answer(false) }
            sendPing { error in deadline.cancel(); answer(error == nil) }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        continuation.yield(.opened)
        let pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else { return }
                if await !self.ping() { webSocketTask.cancel(); self.ended(webSocketTask); return }
            }
        }
        state.withLock { value in if value.finished { pinger.cancel() } else { value.pinger = pinger } }
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(code: closeCode.rawValue == 0 ? nil : closeCode.rawValue, reason: reason.map { String(decoding: $0, as: UTF8.self) }, status: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let task = task as? URLSessionWebSocketTask else { return }
        ended(task)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// A flag that is set once, from any thread.
final class Once: Sendable {
    private let flag = Mutex(false)
    func first() -> Bool { flag.withLock { value in defer { value = true }; return !value } }
}
