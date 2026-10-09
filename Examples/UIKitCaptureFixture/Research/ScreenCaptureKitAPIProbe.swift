// Device-SDK typecheck probe only; not an app target or a production backend.
// This does not establish runtime availability, authorization, or pixel fidelity.
import ScreenCaptureKit

@available(iOS 27, *)
@MainActor
func presentCurrentAppPicker(observer: any SCContentSharingPickerObserver) {
    let picker = SCContentSharingPicker.shared
    var configuration = SCContentSharingPickerConfiguration()
    configuration.showsMicrophoneControl = false
    configuration.showsCameraControl = false
    picker.defaultConfiguration = configuration
    picker.add(observer)
    picker.isActive = true
    picker.presentForCurrentApplication()
}

// Call only after the picker observer supplies the user's selected filter.
@available(iOS 27, *)
func startVideoStream(filter: SCContentFilter, output: any SCStreamOutput) async throws -> SCStream {
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = false
    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "screener.research.frames"))
    try await stream.startCapture()
    return stream
}

@available(iOS 27, *)
@MainActor
func stopVideoStream(_ stream: SCStream, observer: any SCContentSharingPickerObserver) async throws {
    defer {
        SCContentSharingPicker.shared.remove(observer)
        SCContentSharingPicker.shared.isActive = false
    }
    try await stream.stopCapture()
}
