import Foundation

/// One JSON document per trip: <directory>/<trip-uuid>.json
public struct TripRepository {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func loadAll() throws -> [Trip] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(Trip.self, from: try Data(contentsOf: $0)) }
    }

    public func save(_ trip: Trip) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(trip.id.uuidString).json")
        try encoder.encode(trip).write(to: url, options: .atomic)
    }

    public func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Remove every persisted trip document (sign-out / account deletion wipe).
    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
