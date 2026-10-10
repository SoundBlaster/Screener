import CoreGraphics
import Foundation
import ImageIO
import ScreenerCore
import ScreenerMCP

@main
enum ScreenerBenchmarks {
    private struct Options {
        var records = 10_000
        var frames = 400
        var iterations = 100
    }

    static func main() throws {
        let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ScreenerBenchmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = try makeTrace(at: root, recordCount: options.records, frameCount: options.frames)
        let catalog = TraceCatalog(roots: [root])
        let timelineOffset = max(0, options.records - 2_000)
        let contactSheetOffset = max(0, options.frames / 2)

        let timelineSamples = try BenchmarkMeasurement.measure(iterations: options.iterations) {
            try catalog.timelinePage(sessionID: manifest.sessionID, offset: timelineOffset, limit: 2_000)
        }
        let contactSheetSamples = try BenchmarkMeasurement.measure(iterations: options.iterations) {
            try catalog.contactSheet(sessionID: manifest.sessionID, offset: contactSheetOffset, maxCells: 24)
        }

        print("Screener performance benchmark (\(ProcessInfo.processInfo.operatingSystemVersionString))")
        print("Trace: \(options.records) records, \(options.frames) frames; \(BenchmarkMeasurement.warmupIterations) warm-up + \(options.iterations) measured iterations per query")
        print("timelinePage near tail (up to 2,000 records): \(BenchmarkMeasurement.summary(timelineSamples))")
        print("contactSheet page (up to 24 frames):       \(BenchmarkMeasurement.summary(contactSheetSamples))")
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                throw BenchmarkError.usage
            }
            switch arguments[index] {
            case "--records": options.records = value
            case "--frames": options.frames = value
            case "--iterations": options.iterations = value
            default: throw BenchmarkError.usage
            }
            index += 2
        }
        guard options.frames <= options.records else { throw BenchmarkError.usage }
        return options
    }

    private static func makeTrace(at root: URL, recordCount: Int, frameCount: Int) throws -> TraceManifest {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bundle = root.appending(path: "benchmark.vtrace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundle.appending(path: "frames"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.appending(path: "thumbs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle.appending(path: "semantic"), withIntermediateDirectories: true)

        let manifest = TraceManifest(name: "Screener benchmark", appBundleID: "dev.screener.benchmark", platform: "macOS")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: bundle.appending(path: "manifest.json"), options: .atomic)

        let frameData = try makePNG()
        let frameInterval = max(1, recordCount / frameCount)
        var frameIndex = 0
        var timeline = Data()
        for index in 0..<recordCount {
            let isFrame = frameIndex < frameCount && (index % frameInterval == 0 || index == recordCount - 1)
            let blob: String?
            let kind: TraceRecord.Kind
            if isFrame {
                let path = "frames/frame-\(frameIndex).png"
                try frameData.write(to: bundle.appending(path: path), options: .atomic)
                blob = path
                kind = .keyframe
                frameIndex += 1
            } else {
                blob = nil
                kind = .marker
            }

            let record = TraceRecord(
                sequence: UInt64(index),
                timestamp: Date(timeIntervalSince1970: Double(index)),
                monotonicNanoseconds: UInt64(index) * 1_000_000,
                kind: kind,
                name: isFrame ? "Screen \(frameIndex)" : "Event \(index)",
                blob: blob
            )
            timeline.append(try encoder.encode(record))
            timeline.append(0x0A)
        }
        guard frameIndex == frameCount else { throw BenchmarkError.fixtureCreation }
        try timeline.write(to: bundle.appending(path: "timeline.jsonl"), options: .atomic)
        return manifest
    }

    private static func makePNG() throws -> Data {
        guard let context = CGContext(
            data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { throw BenchmarkError.fixtureCreation }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw BenchmarkError.fixtureCreation
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BenchmarkError.fixtureCreation }
        return output as Data
    }

    private enum BenchmarkError: Error, LocalizedError {
        case usage
        case fixtureCreation

        var errorDescription: String? {
            switch self {
            case .usage: "Usage: screener-benchmarks [--records N] [--frames N] [--iterations N] (positive integers; frames <= records)."
            case .fixtureCreation: "Could not create the synthetic benchmark trace."
            }
        }
    }
}
