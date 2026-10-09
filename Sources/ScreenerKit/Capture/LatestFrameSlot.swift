import Foundation

/// Bounded handoff: a slow writer retains only the newest unconsumed frame.
/// The lock protects both the value and the terminal flag.
final class LatestFrameSlot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Value?
    private var closed = false

    func offer(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        pending = value
    }

    func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        defer { pending = nil }
        return pending
    }

    /// Rejects future offers, retaining the last sample for a final drain.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }
}
