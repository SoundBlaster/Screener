import Foundation
import Testing
@testable import ScreenerCore

@Suite("Trace bundle")
struct TraceBundleTests {
    @Test func writerReaderRoundTripAndSequence() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        let manifest = TraceManifest(
            name: "test", appBundleID: "dev.test.app", platform: "macOS",
            startedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let writer = try TraceBundleWriter(url: bundle, manifest: manifest)
        let timestamp = Date(timeIntervalSince1970: 1_760_000_001)
        let first = try await writer.append(
            kind: .marker, name: "ready", metadata: ["screen": "home"], timestamp: timestamp
        )
        let blob = try await writer.writeBlob(Data([0x7F]), kind: .frame, fileExtension: "png")
        let second = try await writer.append(
            kind: .keyframe, name: "manual", blob: blob, timestamp: timestamp
        )

        #expect(first.sequence == 0)
        #expect(second.sequence == 1)
        let decodedManifest = try TraceBundleReader(url: bundle).manifest()
        #expect(decodedManifest.sessionID == manifest.sessionID)
        #expect(decodedManifest.startedAt == manifest.startedAt)
        let decodedRecords = try TraceBundleReader(url: bundle).timeline()
        #expect(decodedRecords.map(\.id) == [first.id, second.id])
        #expect(decodedRecords.map(\.sequence) == [0, 1])
        #expect(decodedRecords.map(\.name) == ["ready", "manual"])
    }

    @Test func ignoresOnlyIncompleteTrailingRecord() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        let writer = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        let record = try await writer.append(
            kind: .marker, name: "valid", timestamp: Date(timeIntervalSince1970: 1_760_000_001)
        )
        let timeline = bundle.appending(path: "timeline.jsonl")
        let handle = try FileHandle(forWritingTo: timeline)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":".utf8))
        try handle.close()

        let records = try TraceBundleReader(url: bundle).timeline()
        #expect(records.map(\.id) == [record.id])
    }

    @Test func rejectsMalformedCompleteRecord() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        _ = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        try Data("{\"broken\":true}\n".utf8).write(to: bundle.appending(path: "timeline.jsonl"))

        #expect(throws: TraceBundleError.malformedRecord(line: 1)) {
            try TraceBundleReader(url: bundle).timeline()
        }
    }

    @Test func rejectsCompleteBlankLineAndReportsItsLineNumber() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        _ = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        try Data("\n".utf8).write(to: bundle.appending(path: "timeline.jsonl"))

        #expect(throws: TraceBundleError.malformedRecord(line: 1)) {
            try TraceBundleReader(url: bundle).timeline()
        }
    }

    @Test func timelineRejectsUnsupportedManifestVersion() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        _ = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        let manifestURL = bundle.appending(path: "manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        object["formatVersion"] = TraceManifest.currentFormatVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        #expect(throws: TraceBundleError.unsupportedFormatVersion(2)) {
            try TraceBundleReader(url: bundle).timeline()
        }
    }

    @Test func skipsUnknownOptionalKindsAndReportsThem() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        let writer = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        let record = try await writer.append(kind: .marker, name: "known")
        let timeline = bundle.appending(path: "timeline.jsonl")
        let handle = try FileHandle(forWritingTo: timeline)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"kind\":\"futureEvent\",\"optional\":true}\n".utf8))
        try handle.close()

        let result = try TraceBundleReader(url: bundle).timelineResult()
        #expect(result.records.map(\.id) == [record.id])
        #expect(result.skippedOptionalKinds == ["futureEvent"])
    }

    @Test func rejectsUnknownRequiredKinds() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        _ = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        try Data("{\"kind\":\"futureEvent\"}\n".utf8).write(to: bundle.appending(path: "timeline.jsonl"))

        #expect(throws: TraceBundleError.malformedRecord(line: 1)) {
            try TraceBundleReader(url: bundle).timeline()
        }
    }

    @Test func rejectsDanglingAndEscapingBlobReferences() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        let writer = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )

        for path in ["frames/missing.png", "../outside", "/tmp/outside"] {
            do {
                _ = try await writer.append(kind: .keyframe, name: "bad", blob: path)
                Issue.record("Expected blob reference to be rejected: \(path)")
            } catch let error as TraceBundleError {
                #expect(error == .invalidBlobReference(path))
            }
        }
        #expect(try TraceBundleReader(url: bundle).timeline().isEmpty)
    }

    @Test func publishesBlobBeforeReturningReference() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "session.vtrace")
        let writer = try TraceBundleWriter(
            url: bundle,
            manifest: TraceManifest(name: "test", appBundleID: "dev.test.app", platform: "macOS")
        )
        let payload = Data([0x01, 0x02, 0x03])
        let relativePath = try await writer.writeBlob(payload, kind: .frame, fileExtension: "png")

        #expect(relativePath.hasPrefix("frames/"))
        #expect(try Data(contentsOf: bundle.appending(path: relativePath)) == payload)
        do {
            _ = try await writer.writeBlob(payload, kind: .frame, fileExtension: "../outside")
            Issue.record("Expected invalid blob extension to be rejected")
        } catch let error as TraceBundleError {
            #expect(error == .invalidBlobExtension)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
