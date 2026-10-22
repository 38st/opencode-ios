import Foundation
import Testing
import OCModels

@Test func serverRecordsContainNoCredentials() throws {
    let record = ServerRecord(name: "Test", endpoints: [.init(url: URL(string: "http://localhost")!, kind: .lan)])
    let encoded = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(ServerRecord.self, from: encoded) == record)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["credential"] == nil)
    #expect(object["password"] == nil)
}

@Test func unknownEndpointKindsRemainReadable() throws {
    #expect(try JSONDecoder().decode(EndpointKind.self, from: Data(#""future""#.utf8)) == .unknown)
    #expect(try JSONDecoder().decode(EndpointSource.self, from: Data(#""future""#.utf8)) == .unknown)
}
