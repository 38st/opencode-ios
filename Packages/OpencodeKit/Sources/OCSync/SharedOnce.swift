import Foundation

/// One value made once for every caller, even callers that arrive together, such as several scenes connecting at
/// launch. A failure is not kept: the next caller tries again.
@MainActor public final class SharedOnce<Value: Sendable> {
    private let make: @MainActor () async throws -> Value
    private var task: Task<Value, any Error>?
    public init(_ make: @escaping @MainActor () async throws -> Value) { self.make = make }
    public func value() async throws -> Value {
        if let task { return try await task.value }
        let created = Task { @MainActor in try await make() }
        task = created
        do { return try await created.value } catch {
            if task == created { task = nil }
            throw error
        }
    }
}
