/// A registry shares one residency budget across all of its servers.
@MainActor public final class TranscriptResidency {
    private struct Entry {
        weak var store: ReadStore?
        let sessionID: String
    }
    private var entries: [Entry] = []
    public init() {}
    func touch(_ store: ReadStore, sessionID: String) -> [(ReadStore, String)] {
        entries.removeAll { entry in
            guard let owner = entry.store else { return true }
            return !owner.lru.contains(entry.sessionID) || (owner === store && entry.sessionID == sessionID)
        }
        entries.append(Entry(store: store, sessionID: sessionID))
        var evicted: [(ReadStore, String)] = []
        while entries.count > 6 {
            let entry = entries.removeFirst()
            if let owner = entry.store { evicted.append((owner, entry.sessionID)) }
        }
        return evicted
    }
}
