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
    AVCaptureDevice.devices(for: .audio)
      .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

