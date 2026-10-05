public enum ScreenerCaptureError: Error, Equatable {
    case emptyBounds
    case incompleteHierarchy
    case imageUnavailable
    case invalidImage
    case encodingFailed
}
