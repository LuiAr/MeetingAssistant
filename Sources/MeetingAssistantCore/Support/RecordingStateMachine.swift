import Foundation

public struct RecordingStateMachine: Equatable, Sendable {
  public private(set) var status: RecordingStatus
  public private(set) var startedAt: Date?
  public private(set) var pausedAt: Date?
  public private(set) var pauses: [PauseInterval]
  public private(set) var errorMessage: String?

  public init(
    status: RecordingStatus = .idle,
    startedAt: Date? = nil,
    pausedAt: Date? = nil,
    pauses: [PauseInterval] = [],
    errorMessage: String? = nil
  ) {
    self.status = status
    self.startedAt = startedAt
    self.pausedAt = pausedAt
    self.pauses = pauses
    self.errorMessage = errorMessage
  }

  public mutating func requestPermissions() {
    status = .requestingPermissions
    errorMessage = nil
  }

  public mutating func start(at date: Date) {
    status = .recording
    startedAt = date
    pausedAt = nil
    pauses = []
    errorMessage = nil
  }

  public mutating func pause(at date: Date) {
    guard status == .recording else { return }
    status = .paused
    pausedAt = date
  }

  public mutating func resume(at date: Date) {
    guard status == .paused, let startedAt, let pausedAt else { return }
    let pause = PauseInterval(
      startedAt: pausedAt,
      endedAt: date,
      startOffset: pausedAt.timeIntervalSince(startedAt),
      endOffset: date.timeIntervalSince(startedAt)
    )
    pauses.append(pause)
    self.pausedAt = nil
    status = .recording
  }

  public mutating func finalize() {
    guard status == .recording || status == .paused else { return }
    status = .finalizing
  }

  public mutating func complete() {
    status = .completed
    pausedAt = nil
  }

  public mutating func fail(_ message: String) {
    status = .failed
    errorMessage = message
    pausedAt = nil
  }

  public func wallElapsed(at date: Date) -> TimeInterval {
    guard let startedAt else { return 0 }
    return max(0, date.timeIntervalSince(startedAt))
  }

  public func activeElapsed(at date: Date) -> TimeInterval {
    guard let startedAt else { return 0 }
    let wallElapsed = max(0, date.timeIntervalSince(startedAt))
    var completedPauses = pauses
    if let pausedAt {
      completedPauses.append(
        PauseInterval(
          startedAt: pausedAt,
          endedAt: date,
          startOffset: pausedAt.timeIntervalSince(startedAt),
          endOffset: date.timeIntervalSince(startedAt)
        )
      )
    }
    return PauseCompactor.activeOffset(for: wallElapsed, pauses: completedPauses)
  }
}

