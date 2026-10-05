import Foundation

/// Serializes trace events into an append-only `.vtrace` directory.
public actor TraceBundleWriter {
    public enum BlobKind: String, Sendable {
        case thumbnail = "thumbs"
        case frame = "frames"
        case semantic = "semantic"
    }

    public let url: URL
    public let manifest: TraceManifest

    private let timelineURL: URL
    private var nextSequence: UInt64 = 0
    private var isClosed = false

    public init(url: URL, manifest: TraceManifest) throws {
        self.url = url
        self.manifest = manifest
        timelineURL = url.appending(path: "timeline.jsonl")

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appending(path: "thumbs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appending(path: "frames"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appending(path: "semantic"), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: url.appending(path: "manifest.json"), options: .atomic)
        guard FileManager.default.createFile(atPath: timelineURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    @discardableResult
    public func append(
        kind: TraceRecord.Kind,
        name: String,
        metadata: [String: String] = [:],
        blob: String? = nil,
        timestamp: Date = .now,
        monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) throws -> TraceRecord {
        guard !isClosed else { throw TraceBundleError.writerClosed }
        if let blob { try validatePublishedBlob(blob) }
        let record = TraceRecord(
            sequence: nextSequence,
            timestamp: timestamp,
            monotonicNanoseconds: monotonicNanoseconds,
            kind: kind,
            name: name,
            metadata: metadata,
            blob: blob
        )
        var data = try Self.encoder.encode(record)
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: timelineURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        nextSequence += 1
        return record
    }

    /// Atomically publishes a blob and returns its bundle-relative path.
    public func writeBlob(_ data: Data, kind: BlobKind, fileExtension: String) throws -> String {
        guard !isClosed else { throw TraceBundleError.writerClosed }
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalizedExtension.isEmpty,
              normalizedExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw TraceBundleError.invalidBlobExtension
        }

        let relativePath = "\(kind.rawValue)/\(UUID().uuidString).\(normalizedExtension.lowercased())"
        let destination = url.appending(path: relativePath)
        try data.write(to: destination, options: .atomic)
        return relativePath
    }

    public func close() {
        isClosed = true
    }

    private func validatePublishedBlob(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw TraceBundleError.invalidBlobReference(path)
        }

        let bundlePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let blobURL = url.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
        guard blobURL.path.hasPrefix(bundlePath + "/"),
              let values = try? blobURL.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            throw TraceBundleError.invalidBlobReference(path)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
