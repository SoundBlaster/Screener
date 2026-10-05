import Foundation
import Testing
import ScreenerCore
@testable import ScreenerMCP

@Suite("Screener MCP trace catalog")
struct TraceCatalogTests {
    @Test func discoversSessionAndReadsFrameFromConfiguredRoot() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "nested/run.vtrace", directoryHint: .isDirectory)
        let manifest = TraceManifest(name: "fixture", appBundleID: "dev.test", platform: "iOS")
        let writer = try TraceBundleWriter(url: bundle, manifest: manifest)
        let blob = try await writer.writeBlob(Data([0x89, 0x50, 0x4E, 0x47]), kind: .frame, fileExtension: "png")
        let frame = try await writer.append(kind: .keyframe, name: "home", blob: blob)

        let catalog = TraceCatalog(roots: [root])
        #expect(catalog.sessions().map(\.id) == [manifest.sessionID])
        #expect(try catalog.timeline(sessionID: manifest.sessionID).map(\.id) == [frame.id])
        let result = try catalog.frame(sessionID: manifest.sessionID, recordID: frame.id)
        #expect(result.record.name == "home")
        #expect(result.mimeType == "image/png")
        #expect(result.data == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func doesNotFollowFrameSymlinkOutsideBundle() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace", directoryHint: .isDirectory)
        let manifest = TraceManifest(name: "fixture", appBundleID: "dev.test", platform: "iOS")
        let writer = try TraceBundleWriter(
            url: bundle,
            manifest: manifest
        )
        let sessionID = manifest.sessionID
        let blob = try await writer.writeBlob(Data([1]), kind: .frame, fileExtension: "png")
        let record = try await writer.append(kind: .keyframe, name: "home", blob: blob)
        let outside = root.appending(path: "outside.png")
        try Data([2]).write(to: outside)
        try FileManager.default.removeItem(at: bundle.appending(path: blob))
        try FileManager.default.createSymbolicLink(at: bundle.appending(path: blob), withDestinationURL: outside)

        #expect(throws: TraceCatalogError.invalidFrameReference) {
            _ = try TraceCatalog(roots: [root]).frame(sessionID: sessionID, recordID: record.id)
        }
    }

    @Test func enforcesFrameSizeLimitAndRejectsUnknownImageTypes() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace", directoryHint: .isDirectory)
        let manifest = TraceManifest(name: "fixture", appBundleID: "dev.test", platform: "iOS")
        let writer = try TraceBundleWriter(
            url: bundle,
            manifest: manifest
        )
        let sessionID = manifest.sessionID
        let blob = try await writer.writeBlob(Data([1, 2, 3]), kind: .frame, fileExtension: "bin")
        let record = try await writer.append(kind: .keyframe, name: "home", blob: blob)

        #expect(throws: TraceCatalogError.frameTooLarge) {
            _ = try TraceCatalog(roots: [root], maximumFrameBytes: 2).frame(
                sessionID: sessionID, recordID: record.id
            )
        }
        #expect(throws: TraceCatalogError.unsupportedFrameType) {
            _ = try TraceCatalog(roots: [root]).frame(
                sessionID: sessionID, recordID: record.id
            )
        }
    }

    @Test func ignoresMissingRootsAndReturnsEmptyCatalog() {
        let missing = URL(fileURLWithPath: "/path/that/does/not/exist")
        #expect(TraceCatalog(roots: [missing]).sessions().isEmpty)
    }

    @Test func doesNotDiscoverBundlesThroughDirectorySymlinks() async throws {
        let root = try temporaryDirectory()
        let external = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let bundle = external.appending(path: "hidden.vtrace", directoryHint: .isDirectory)
        _ = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "external", appBundleID: "dev.test", platform: "iOS")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "external-link"),
            withDestinationURL: external
        )

        #expect(TraceCatalog(roots: [root]).sessions().isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
