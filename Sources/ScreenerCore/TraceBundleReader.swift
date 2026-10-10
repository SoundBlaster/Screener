import Foundation

/// Reads manifests and complete timeline records from an existing trace bundle.
public struct TraceBundleReader: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Decodes the manifest and rejects an unsupported trace format version.
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
        try timelineResult().records
    }

    /// Returns known records and the names of explicitly optional kinds skipped while reading.
    public func timelineResult() throws -> TraceTimeline {
        _ = try manifest()
        let timelineURL = url.appending(path: "timeline.jsonl")
        guard FileManager.default.fileExists(atPath: timelineURL.path) else {
            throw TraceBundleError.invalidBundle(url)
        }
        let bytes = try Data(contentsOf: timelineURL)
        let lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false).dropLast()

        var records: [TraceRecord] = []
        var skippedOptionalKinds: [String] = []
        for (index, line) in lines.enumerated() {
            do {
                let data = Data(line)
                let header = try Self.decoder.decode(TimelineHeader.self, from: data)
                if !Self.knownKinds.contains(header.kind) {
                    guard header.optional == true else {
                        throw TraceBundleError.malformedRecord(line: index + 1)
                    }
                    skippedOptionalKinds.append(header.kind)
                    continue
                }
                records.append(try Self.decoder.decode(TraceRecord.self, from: data))
            } catch let error as TraceBundleError {
                throw error
            } catch {
                throw TraceBundleError.malformedRecord(line: index + 1)
            }
        }
        return TraceTimeline(records: records, skippedOptionalKinds: skippedOptionalKinds)
    }

    private static let knownKinds: Set<String> = ["sessionStarted", "marker", "sessionEnded", "thumbnail", "keyframe"]

    private struct TimelineHeader: Decodable {
        let kind: String
        let optional: Bool?
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

public struct TraceTimeline: Sendable, Equatable {
    public let records: [TraceRecord]
    public let skippedOptionalKinds: [String]

    public init(records: [TraceRecord], skippedOptionalKinds: [String] = []) {
        self.records = records
        self.skippedOptionalKinds = skippedOptionalKinds
    }
}
