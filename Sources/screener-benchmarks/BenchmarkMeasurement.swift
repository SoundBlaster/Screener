import Foundation

/// Warm-cache query measurements; fixture creation is excluded by the caller.
enum BenchmarkMeasurement {
    static let warmupIterations = 3
    static let minimumPercentileSamples = 100

    static func measure<T>(iterations: Int, operation: () throws -> T) throws -> [Double] {
        // Warm up each query independently, without adding warm-up runs to the samples.
        for _ in 0..<warmupIterations {
            _ = try operation()
        }
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            _ = try operation()
            let components = start.duration(to: .now).components
            samples.append(Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15)
        }
        return samples
    }

    static func summary(_ samples: [Double]) -> String {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        let tailLabel: String
        let tail: Double
        if sorted.count >= minimumPercentileSamples {
            tailLabel = "p95"
            tail = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
        } else {
            tailLabel = "max"
            tail = sorted[sorted.count - 1]
        }
        return "median \(String(format: "%.2f", median)) ms, \(tailLabel) \(String(format: "%.2f", tail)) ms"
    }
}
