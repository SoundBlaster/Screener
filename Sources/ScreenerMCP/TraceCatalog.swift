import Foundation
import ScreenerCore

public struct TraceSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let appBundleID: String
    public let platform: String
    public let startedAt: Date
    public let screenerVersion: String
}

public enum TraceCatalogError: Error, Equatable, LocalizedError {
    case sessionNotFound(UUID)
    case recordNotFound(UUID)
    case invalidFrameReference
    case frameTooLarge
    case unsupportedFrameType

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id): "No local trace session found for \(id)."
        case .recordNotFound(let id): "No frame record found for \(id)."
        case .invalidFrameReference: "The frame blob reference is invalid or points outside its trace bundle."
        case .frameTooLarge: "The frame exceeds the configured MCP image size limit."
        case .unsupportedFrameType: "Only PNG and JPEG frames can be returned by MCP."
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
        let bundle = try bundle(for: sessionID)
        return Array(try TraceBundleReader(url: bundle).timeline().prefix(max(1, min(limit, 2_000))))
    }

    public func frame(sessionID: UUID, recordID: UUID) throws -> (record: TraceRecord, data: Data, mimeType: String) {
        let bundle = try bundle(for: sessionID)
        guard let record = try TraceBundleReader(url: bundle).timeline().first(where: { $0.id == recordID }),
              record.kind == .keyframe || record.kind == .thumbnail,
              let relativePath = record.blob else {
            throw TraceCatalogError.recordNotFound(recordID)
        }

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
