import Foundation
import Testing
import ImageIO
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

    @Test func timelinePagesKeepLaterRecordsReachableInChronologicalOrder() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = TraceManifest(name: "paged", appBundleID: "dev.test", platform: "iOS")
        let writer = try TraceBundleWriter(
            url: root.appending(path: "paged.vtrace", directoryHint: .isDirectory),
            manifest: manifest
        )
        var expectedIDs: [UUID] = []
        for index in 0..<5 {
            let record = try await writer.append(kind: .marker, name: "event-\(index)")
            expectedIDs.append(record.id)
        }

        let firstPage = try TraceCatalog(roots: [root]).timelinePage(
            sessionID: manifest.sessionID, limit: 2
        )
        let secondPage = try TraceCatalog(roots: [root]).timelinePage(
            sessionID: manifest.sessionID, offset: try #require(firstPage.nextOffset), limit: 2
        )
        let lastPage = try TraceCatalog(roots: [root]).timelinePage(
            sessionID: manifest.sessionID, offset: try #require(secondPage.nextOffset), limit: 2
        )

        #expect(firstPage.records.map(\.id) == Array(expectedIDs[0..<2]))
        #expect(secondPage.records.map(\.id) == Array(expectedIDs[2..<4]))
        #expect(lastPage.records.map(\.id) == [expectedIDs[4]])
        #expect(firstPage.totalRecords == 5)
        #expect(lastPage.nextOffset == nil)
    }

    @Test func contactSheetContainsChronologicalFrameMapAndCanBePaged() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = TraceManifest(name: "visual", appBundleID: "dev.test", platform: "iOS")
        let writer = try TraceBundleWriter(
            url: root.appending(path: "visual.vtrace", directoryHint: .isDirectory),
            manifest: manifest
        )
        var expected: [UUID] = []
        for (index, kind) in [TraceRecord.Kind.keyframe, .thumbnail, .keyframe].enumerated() {
            let blobKind: TraceBundleWriter.BlobKind = kind == .thumbnail ? .thumbnail : .frame
            let blob = try await writer.writeBlob(
                makeTestPNG(red: CGFloat(index) * 0.2), kind: blobKind, fileExtension: "png"
            )
            let record = try await writer.append(kind: kind, name: "screen-\(index)", blob: blob)
            expected.append(record.id)
        }

        let catalog = TraceCatalog(roots: [root])
        let firstPage = try catalog.contactSheet(
            sessionID: manifest.sessionID, maxCells: 2, columns: 2
        )
        #expect(firstPage.page.cells.map(\.id) == Array(expected[0..<2]))
        #expect(firstPage.page.cells.map(\.index) == [1, 2])
        #expect(firstPage.page.totalFrames == 3)
        #expect(firstPage.page.nextOffset == 2)
        let firstImageSource = try #require(CGImageSourceCreateWithData(firstPage.imageData as CFData, nil))
        let firstImage = try #require(CGImageSourceCreateImageAtIndex(firstImageSource, 0, nil))
        #expect(firstImage.width == 568)

        let secondPage = try catalog.contactSheet(sessionID: manifest.sessionID, offset: 2)
        #expect(secondPage.page.cells.map(\.id) == [expected[2]])
        #expect(secondPage.page.nextOffset == nil)
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
