import AVFoundation
import Foundation

public struct MicrophoneDevice: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public enum MicrophoneDeviceProvider {
  public static func devices() -> [MicrophoneDevice] {
    // `AVCaptureDevice.devices(for:)` is deprecated; use a discovery session, which is the
    // supported way to enumerate audio input devices on macOS 15+.
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.microphone, .external],
      mediaType: .audio,
      position: .unspecified
    )
    return discovery.devices
      .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

