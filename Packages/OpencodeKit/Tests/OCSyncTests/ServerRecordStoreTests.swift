import Testing
import OCModels
import OCPersistence
import OCSync

struct ServerRecordStoreTests {
    @Test func actorWitnessesKeepTheirIsolation() async throws {
        let store: any ServerRecordStore = IsolatedRecords()
        let record = syncRecord()
        try await store.save([record])
        #expect(try await store.load().map(\.id) == [record.id])
        try await checkFromMainActor(store, record: record)
    }

    @MainActor private func checkFromMainActor(_ store: any ServerRecordStore, record: ServerRecord) async throws {
        #expect(try await store.load().map(\.id) == [record.id])
        try await store.save([])
        #expect(try await store.load().isEmpty)
    }
}

// Deliberately uses a synthesized initializer to cover the Xcode 27.0 regression.
private actor IsolatedRecords: ServerRecordStore {
    var records: [ServerRecord] = []
    func load() -> [ServerRecord] {
        assertIsolated()
        return records
    }
    func save(_ records: [ServerRecord]) {
        assertIsolated()
        self.records = records
    }
}
