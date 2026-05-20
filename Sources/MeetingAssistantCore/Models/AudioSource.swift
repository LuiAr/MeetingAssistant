import Foundation

public enum AudioSource: String, Codable, CaseIterable, Identifiable, Sendable {
  case system
  case microphone
  case mixed

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .system:
      return "Computer audio"
    case .microphone:
      return "You"
    case .mixed:
      return "Mixed"
    }
  }

  public var speakerLabel: SpeakerLabel {
    switch self {
    case .system:
      return .computerAudio
    case .microphone:
      return .you
    case .mixed:
      return .mixed
    }
  }
}

