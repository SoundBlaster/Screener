import Testing
@testable import screener_benchmarks

struct BenchmarkMeasurementTests {
    @Test func warmupRunsAreExcludedFromSampleCount() throws {
        var calls = 0
        let samples = try BenchmarkMeasurement.measure(iterations: 7) { calls += 1 }
        #expect(calls == 10)
        #expect(samples.count == 7)
    }

    @Test func smallSamplesReportMaximum() {
        #expect(BenchmarkMeasurement.summary([7, 1, 6, 2, 5, 3, 4]) == "median 4.00 ms, max 7.00 ms")
        #expect(BenchmarkMeasurement.summary([2]) == "median 2.00 ms, max 2.00 ms")
        #expect(BenchmarkMeasurement.summary([4, 2]) == "median 3.00 ms, max 4.00 ms")
        #expect(BenchmarkMeasurement.summary(Array(1...99).map(Double.init)).contains("max 99.00 ms"))
    }

    @Test func sufficientSamplesReportNearestRankP95() {
        let samples = Array(1...100).reversed().map(Double.init)
        #expect(BenchmarkMeasurement.summary(samples) == "median 50.50 ms, p95 95.00 ms")
    }

    @Test func warmupFailurePropagatesBeforeMeasurement() {
        enum Failure: Error { case expected }
        var calls = 0
        #expect(throws: Failure.self) {
            try BenchmarkMeasurement.measure(iterations: 7) {
                calls += 1
                throw Failure.expected
            }
        }
        #expect(calls == 1)
    }
}
