import Foundation

/// An ordered event with timestamps, semantic metadata, and an optional blob reference.
public struct TraceRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case sessionStarted
        case marker
        case sessionEnded
        case thumbnail
        case keyframe
    }

    public let id: UUID
    public let sequence: UInt64
    public let timestamp: Date
    public let monotonicNanoseconds: UInt64
    public let kind: Kind
    public let name: String
    public let metadata: [String: String]
    public let blob: String?

    public init(
        id: UUID = UUID(),
        sequence: UInt64,
        timestamp: Date = .now,
        monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
        kind: Kind,
        name: String,
        metadata: [String: String] = [:],
        blob: String? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.monotonicNanoseconds = monotonicNanoseconds
        self.kind = kind
        self.name = name
        self.metadata = metadata
        self.blob = blob
    }
}
