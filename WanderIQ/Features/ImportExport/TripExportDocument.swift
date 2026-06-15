import SwiftUI
import UniformTypeIdentifiers

/// Minimal document wrapper so SwiftUI's `.fileExporter` can write the codec's
/// bytes (JSON or CSV). Read support is unused (import uses `.fileImporter`).
struct TripExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
