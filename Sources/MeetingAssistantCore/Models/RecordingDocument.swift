import Foundation

public struct RecordingDocument: Codable, Identifiable, Equatable, Sendable {
  public var metadata: RecordingMetadata
  public var pauses: [PauseInterval]
  public var transcript: [TranscriptSegment]

  public init(
    metadata: RecordingMetadata,
    pauses: [PauseInterval] = [],
    transcript: [TranscriptSegment] = []
  ) {
    self.metadata = metadata
    self.pauses = pauses
    self.transcript = transcript
  }

  public var id: UUID { metadata.id }
}

