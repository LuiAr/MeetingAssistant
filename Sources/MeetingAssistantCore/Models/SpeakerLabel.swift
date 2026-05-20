import Foundation

public enum SpeakerLabel: String, Codable, CaseIterable, Identifiable, Sendable {
  case you = "You"
  case computerAudio = "Computer audio"
  case mixed = "Mixed"

  public var id: String { rawValue }
}

