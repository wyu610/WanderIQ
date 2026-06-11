import Foundation
import Testing
@testable import PlanovaKit

@Suite struct TripRepositoryTests {

    private var tempDir: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("planova-tests-\(UUID().uuidString)")
    }

    @Test func testSaveAndLoadRoundTrip() throws {
        let dir = tempDir
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = TripRepository(directory: dir)
        let trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0),
                        endDate: Date(timeIntervalSince1970: 86_400),
                        items: [ChecklistItem(kind: .prep, label: "p")])

        try repo.save(trip)
        let loaded = try repo.loadAll()

        #expect(loaded == [trip])
    }

    @Test func testLoadAllFromMissingDirectoryReturnsEmpty() throws {
        let dir = tempDir
        let repo = TripRepository(directory: dir)
        #expect(try repo.loadAll() == [])
    }

    @Test func testDeleteRemovesFile() throws {
        let dir = tempDir
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = TripRepository(directory: dir)
        let trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        try repo.save(trip)

        try repo.delete(id: trip.id)

        #expect(try repo.loadAll() == [])
    }

    @Test func testSaveOverwritesExisting() throws {
        let dir = tempDir
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = TripRepository(directory: dir)
        var trip = Trip(name: "T", startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1))
        try repo.save(trip)
        trip.name = "Renamed"

        try repo.save(trip)

        #expect(try repo.loadAll().first?.name == "Renamed")
    }
}
