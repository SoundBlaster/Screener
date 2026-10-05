import Foundation

public enum TraceBundleError: Error, Equatable {
    case unsupportedFormatVersion(Int)
    case invalidBundle(URL)
    case malformedRecord(line: Int)
    case writerClosed
    case invalidBlobExtension
}
