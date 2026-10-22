import Foundation
import Testing
@testable import OCFoundation

struct SemVerTests {
    @Test func releaseVersionsAndCanonicalPrereleaseOrdering() throws {
        #expect(try #require(SemVer("1.19.1")) < #require(SemVer("2.0.30")))
        let ordered = [
            "2.0.30-alpha", "2.0.30-alpha.1", "2.0.30-alpha.beta", "2.0.30-beta",
            "2.0.30-beta.2", "2.0.30-beta.11", "2.0.30-rc.1", "2.0.30",
        ].compactMap(SemVer.init)
        #expect(ordered.count == 8)
        for (a, b) in zip(ordered, ordered.dropFirst()) { #expect(a < b) }
        #expect(try #require(SemVer("1.0.0-99999999999999999999999")) < #require(SemVer("1.0.0-100000000000000000000000")))
    }

    @Test func metadataHasNoEffectOnPrecedenceAndRoundTrips() throws {
        let a = try #require(SemVer("2.0.30-rc.1+build.001"))
        let b = try #require(SemVer("2.0.30-rc.1+other"))
        #expect(a == b && !(a < b) && !(b < a))
        #expect(Set([a, b]).count == 1)
        #expect(a.major == 2 && a.minor == 0 && a.patch == 30)
        #expect(a.prerelease == ["rc", "1"])
        #expect(a.buildMetadata == ["build", "001"])
        let roundTrip = try JSONDecoder().decode(SemVer.self, from: JSONEncoder().encode(a))
        #expect(roundTrip.description == "2.0.30-rc.1+build.001")
    }

    @Test(arguments: ["", "2", "2.0", "v2.0.30", "2.00.30", "-1.0.0", "1.0.0-", "1.0.0-01", "1.0.0+", "1.0.0+a+b", "1.0.0-a..b", "1.0.0-β", "1.0.0 ", "99999999999999999999999.0.0"])
    func invalidVersionsAreRejected(text: String) throws {
        #expect(SemVer(text) == nil)
        let encoded = try JSONEncoder().encode(text)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SemVer.self, from: encoded) }
    }
}
