import Foundation

public enum PauseCompactor {
  public static func activeOffset(for wallOffset: TimeInterval, pauses: [PauseInterval]) -> TimeInterval {
    let pausedBeforeOffset = pauses.reduce(TimeInterval.zero) { partial, pause in
      guard pause.startOffset < wallOffset else { return partial }
      let pauseEnd = min(pause.endOffset, wallOffset)
      return partial + max(0, pauseEnd - pause.startOffset)
    }

    return max(0, wallOffset - pausedBeforeOffset)
  }

  public static func compact(_ segments: [TranscriptSegment], pauses: [PauseInterval]) -> [TranscriptSegment] {
    segments.map { segment in
      var compacted = segment
      compacted.startTime = activeOffset(for: segment.startTime, pauses: pauses)
      if let endTime = segment.endTime {
        compacted.endTime = activeOffset(for: endTime, pauses: pauses)
      }
      return compacted
    }
  }

  public static func wallOffset(forActiveOffset activeOffset: TimeInterval, pauses: [PauseInterval]) -> TimeInterval {
    var wallOffset = max(0, activeOffset)
    var elapsedPause = TimeInterval.zero

    for pause in pauses.sorted(by: { $0.startOffset < $1.startOffset }) {
      let activePauseStart = max(0, pause.startOffset - elapsedPause)
      guard activeOffset >= activePauseStart else { break }
      let duration = max(0, pause.endOffset - pause.startOffset)
      wallOffset += duration
      elapsedPause += duration
    }

    return wallOffset
  }
}
