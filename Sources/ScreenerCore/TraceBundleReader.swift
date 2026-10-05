import Foundation

public struct TraceBundleReader: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func manifest() throws -> TraceManifest {
        let data = try Data(contentsOf: url.appending(path: "manifest.json"))
        let decoder = Self.decoder
        let manifest = try decoder.decode(TraceManifest.self, from: data)
        guard manifest.formatVersion == TraceManifest.currentFormatVersion else {
            throw TraceBundleError.unsupportedFormatVersion(manifest.formatVersion)
        }
        return manifest
    }

    /// Reads complete JSONL records. A trailing unterminated line is ignored because
    /// the writer may have been interrupted while appending it.
    public func timeline() throws -> [TraceRecord] {
        let timelineURL = url.appending(path: "timeline.jsonl")
        guard FileManager.default.fileExists(atPath: timelineURL.path) else {
            throw TraceBundleError.invalidBundle(url)
        }
        let bytes = try Data(contentsOf: timelineURL)
        var lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: true)
        if bytes.last != 0x0A { lines = Array(lines.dropLast()) }

        return try lines.enumerated().map { index, line in
            do { return try Self.decoder.decode(TraceRecord.self, from: Data(line)) }
            catch { throw TraceBundleError.malformedRecord(line: index + 1) }
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp")
            }
            return date
        }
        return decoder
    }
}
