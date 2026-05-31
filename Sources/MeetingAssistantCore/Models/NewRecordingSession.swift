import Foundation

/// Value passed via `openWindow(id:value:)` to the dedicated Recording window. The `id` is
/// used by SwiftUI as the WindowGroup key (so reopening the same session reuses the same
/// window) and is generated fresh each time the user taps Start Recording on the landing
/// view. The remaining fields configure the auto-started recording.
public struct NewRecordingSession: Hashable, Codable, Sendable, Identifiable {
  public let id: UUID
  public let title: String
  public let localeIdentifier: String
  public let microphoneDeviceID: String?

  public init(
    id: UUID = UUID(),
    title: String,
    localeIdentifier: String,
    microphoneDeviceID: String?
  ) {
    self.id = id
    self.title = title
    self.localeIdentifier = localeIdentifier
    self.microphoneDeviceID = microphoneDeviceID
  }
}
