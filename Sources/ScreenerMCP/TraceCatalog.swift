import Foundation
import CoreGraphics
import ImageIO
import ScreenerCore

public struct TraceSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let appBundleID: String
    public let platform: String
    public let startedAt: Date
    public let screenerVersion: String
}

public struct TraceTimelinePage: Codable, Sendable, Equatable {
    public let records: [TraceRecord]
    public let offset: Int
    public let nextOffset: Int?
    public let totalRecords: Int
}

public struct TraceContactSheetCell: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let index: Int
    public let sequence: UInt64
    public let timestamp: Date
    public let name: String
    public let kind: TraceRecord.Kind
}

public struct TraceContactSheetPage: Codable, Sendable, Equatable {
    public let cells: [TraceContactSheetCell]
    public let offset: Int
    public let nextOffset: Int?
    public let totalFrames: Int
    public let columns: Int
}

public struct TraceContactSheetResult: Sendable {
    public let page: TraceContactSheetPage
    public let imageData: Data
}

public enum TraceCatalogError: Error, Equatable, LocalizedError {
    case sessionNotFound(UUID)
    case recordNotFound(UUID)
    case invalidFrameReference
    case frameTooLarge
    case unsupportedFrameType
    case invalidFrameImage

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id): "No local trace session found for \(id)."
        case .recordNotFound(let id): "No frame record found for \(id)."
        case .invalidFrameReference: "The frame blob reference is invalid or points outside its trace bundle."
        case .frameTooLarge: "The frame exceeds the configured MCP image size limit."
        case .unsupportedFrameType: "Only PNG and JPEG frames can be returned by MCP."
        case .invalidFrameImage: "The recorded frame could not be decoded as an image."
        }
    }
}

/// Reads `.vtrace` bundles beneath explicitly configured local roots.
public struct TraceCatalog: Sendable {
    public static let defaultRoots: [URL] = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appending(path: "Library/Caches", directoryHint: .isDirectory)
        return [
            caches.appending(path: "Screener/Traces", directoryHint: .isDirectory),
            caches.appending(path: "ScreenerFixture/Traces", directoryHint: .isDirectory),
        ]
    }()

    public let roots: [URL]
    public let maximumFrameBytes: Int

    public init(roots: [URL] = TraceCatalog.defaultRoots, maximumFrameBytes: Int = 32 * 1024 * 1024) {
        self.roots = roots
        self.maximumFrameBytes = maximumFrameBytes
    }

    public func sessions() -> [TraceSession] {
        let sessions = discoverBundles().compactMap { url -> TraceSession? in
            guard let manifest = try? TraceBundleReader(url: url).manifest() else { return nil }
            return TraceSession(
                id: manifest.sessionID,
                name: manifest.name,
                appBundleID: manifest.appBundleID,
                platform: manifest.platform,
                startedAt: manifest.startedAt,
                screenerVersion: manifest.screenerVersion
            )
        }.sorted { $0.startedAt > $1.startedAt }
        var seen = Set<UUID>()
        return sessions.filter { seen.insert($0.id).inserted }
    }

    public func timeline(sessionID: UUID, limit: Int = 500) throws -> [TraceRecord] {
        try timelinePage(sessionID: sessionID, limit: limit).records
    }

    public func timelinePage(sessionID: UUID, offset: Int = 0, limit: Int = 500) throws -> TraceTimelinePage {
        let bundle = try bundle(for: sessionID)
        let allRecords = try TraceBundleReader(url: bundle).timeline()
        let start = min(max(0, offset), allRecords.count)
        let end = min(start + max(1, min(limit, 2_000)), allRecords.count)
        return TraceTimelinePage(
            records: Array(allRecords[start..<end]),
            offset: start,
            nextOffset: end < allRecords.count ? end : nil,
            totalRecords: allRecords.count
        )
    }

    public func frame(sessionID: UUID, recordID: UUID) throws -> (record: TraceRecord, data: Data, mimeType: String) {
        let bundle = try bundle(for: sessionID)
        guard let record = try TraceBundleReader(url: bundle).timeline().first(where: { $0.id == recordID }),
              record.kind == .keyframe || record.kind == .thumbnail,
              let relativePath = record.blob else {
            throw TraceCatalogError.recordNotFound(recordID)
        }

        return try frame(record: record, relativePath: relativePath, bundle: bundle)
    }

    public func contactSheet(
        sessionID: UUID,
        offset: Int = 0,
        maxCells: Int = 24,
        columns: Int = 4
    ) throws -> TraceContactSheetResult {
        let bundle = try bundle(for: sessionID)
        let allFrames = try TraceBundleReader(url: bundle).timeline().filter {
            ($0.kind == .keyframe || $0.kind == .thumbnail) && $0.blob != nil
        }
        let start = min(max(0, offset), allFrames.count)
        let count = max(1, min(maxCells, 24))
        let end = min(start + count, allFrames.count)
        let selected = allFrames[start..<end]
        let columnCount = max(1, min(columns, min(6, max(1, selected.count))))
        var thumbnails: [(TraceContactSheetCell, Data)] = []
        for (position, record) in selected.enumerated() {
            guard let relativePath = record.blob else { continue }
            let frameData = try frame(record: record, relativePath: relativePath, bundle: bundle)
            let thumbnail = try Self.downsample(frameData.data, maximumPixelSize: 256)
            thumbnails.append((
                TraceContactSheetCell(
                    id: record.id,
                    index: start + position + 1,
                    sequence: record.sequence,
                    timestamp: record.timestamp,
                    name: record.name,
                    kind: record.kind
                ),
                thumbnail
            ))
        }

        let cells = thumbnails.map(\.0)
        let page = TraceContactSheetPage(
            cells: cells,
            offset: start,
            nextOffset: end < allFrames.count ? end : nil,
            totalFrames: allFrames.count,
            columns: columnCount
        )
        let image = try ContactSheetRenderer.render(thumbnails, columns: columnCount)
        return TraceContactSheetResult(page: page, imageData: image)
    }

    private func frame(record: TraceRecord, relativePath: String, bundle: URL) throws -> (record: TraceRecord, data: Data, mimeType: String) {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw TraceCatalogError.invalidFrameReference
        }

        let bundleURL = bundle.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = bundle.appending(path: relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(bundleURL.path + "/"),
              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize else {
            throw TraceCatalogError.invalidFrameReference
        }
        guard fileSize <= maximumFrameBytes else { throw TraceCatalogError.frameTooLarge }

        let ext = fileURL.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "png": mimeType = "image/png"
        case "jpg", "jpeg": mimeType = "image/jpeg"
        default: throw TraceCatalogError.unsupportedFrameType
        }
        return (record, try Data(contentsOf: fileURL), mimeType)
    }

    private static func downsample(_ data: Data, maximumPixelSize: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                ] as CFDictionary
              ) else {
            throw TraceCatalogError.invalidFrameImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw TraceCatalogError.invalidFrameImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TraceCatalogError.invalidFrameImage }
        return output as Data
    }

    private func bundle(for sessionID: UUID) throws -> URL {
        for url in discoverBundles() {
            guard let manifest = try? TraceBundleReader(url: url).manifest(), manifest.sessionID == sessionID else { continue }
            return url
        }
        throw TraceCatalogError.sessionNotFound(sessionID)
    }

    private func discoverBundles() -> [URL] {
        var result: [URL] = []
        for root in roots {
            let root = root.standardizedFileURL
            guard let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isDirectory == true else { continue }
                if url.pathExtension == "vtrace" {
                    result.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}
