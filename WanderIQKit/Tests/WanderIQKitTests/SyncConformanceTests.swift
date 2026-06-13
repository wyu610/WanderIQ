import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncConformanceTests {

    struct Scenario: Decodable {
        let name: String
        let localModifiedAt: Double?
        let tombstone: Double?
        let remoteModifiedAt: Double
        let remoteDeleted: Bool
        let expect: String
    }
    struct Suite_: Decodable { let scenarios: [Scenario] }

    static func load() throws -> [Scenario] {
        let url = Bundle.module.url(forResource: "sync-conformance", withExtension: "json",
                                    subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Suite_.self, from: data).scenarios
    }

    @Test func allConformanceScenariosMatch() throws {
        for s in try Self.load() {
            let decision = ConflictResolver.resolve(
                localModifiedAt: s.localModifiedAt.map { Date(timeIntervalSince1970: $0) },
                tombstone: s.tombstone.map { Date(timeIntervalSince1970: $0) },
                remoteModifiedAt: Date(timeIntervalSince1970: s.remoteModifiedAt),
                remoteDeleted: s.remoteDeleted)
            let expected: ConflictResolver.Decision = s.expect == "applyRemote" ? .applyRemote : .keepLocal
            #expect(decision == expected, "scenario: \(s.name)")
        }
    }
}
