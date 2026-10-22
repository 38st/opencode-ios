import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor public protocol BackgroundTaskProviding {
    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Int
    func end(_ identifier: Int)
}

@MainActor public final class SystemBackgroundTaskProvider: BackgroundTaskProviding {
    public init() {}
    public func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Int {
        #if os(iOS)
        return UIApplication.shared.beginBackgroundTask(withName: "Pause server connections", expirationHandler: expiration).rawValue
        #else
        return 0
        #endif
    }
    public func end(_ identifier: Int) {
        #if os(iOS)
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: identifier))
        #endif
    }
}
