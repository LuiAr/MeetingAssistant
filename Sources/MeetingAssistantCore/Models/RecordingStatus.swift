import Foundation

public enum RecordingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
  case idle
  case requestingPermissions
  case recording
  case paused
  case finalizing
  case completed
  case failed

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .idle:
      return "Idle"
    case .requestingPermissions:
      return "Requesting permissions"
    case .recording:
      return "Recording"
    case .paused:
      return "Paused"
    case .finalizing:
      return "Finalizing"
    case .completed:
      return "Completed"
    case .failed:
      return "Failed"
    }
  }
}

