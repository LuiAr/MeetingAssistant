import Foundation

public struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var startTime: TimeInterval
  public var endTime: TimeInterval?
  public var speaker: SpeakerLabel
  public var text: String
  public var confidence: Double?
  public var isFinal: Bool

  public init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    endTime: TimeInterval? = nil,
    speaker: SpeakerLabel,
    text: String,
    confidence: Double? = nil,
    isFinal: Bool = true
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.speaker = speaker
    self.text = text
    self.confidence = confidence
    self.isFinal = isFinal
  }
}

