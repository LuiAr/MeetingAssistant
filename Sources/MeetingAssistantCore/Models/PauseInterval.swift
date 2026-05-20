import Foundation

public struct PauseInterval: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var startedAt: Date
  public var endedAt: Date
  public var startOffset: TimeInterval
  public var endOffset: TimeInterval

  public init(
    id: UUID = UUID(),
    startedAt: Date,
    endedAt: Date,
    startOffset: TimeInterval,
    endOffset: TimeInterval
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.startOffset = startOffset
    self.endOffset = endOffset
  }

  public var duration: TimeInterval {
    max(0, endedAt.timeIntervalSince(startedAt))
  }
}

