import Foundation
import Testing
@testable import MeetingAssistantCore

@Suite("PauseCompactor")
struct PauseCompactorTests {
  @Test
  func removesCompletedPauseDurationsFromOffsets() {
    let start = Date(timeIntervalSince1970: 100)
    let pause = PauseInterval(
      startedAt: start.addingTimeInterval(10),
      endedAt: start.addingTimeInterval(20),
      startOffset: 10,
      endOffset: 20
    )

    #expect(PauseCompactor.activeOffset(for: 5, pauses: [pause]) == 5)
    #expect(PauseCompactor.activeOffset(for: 15, pauses: [pause]) == 10)
    #expect(PauseCompactor.activeOffset(for: 25, pauses: [pause]) == 15)
  }

  @Test
  func roundTripsActiveOffsetsBackToWallOffsets() {
    let start = Date(timeIntervalSince1970: 100)
    let pause = PauseInterval(
      startedAt: start.addingTimeInterval(10),
      endedAt: start.addingTimeInterval(20),
      startOffset: 10,
      endOffset: 20
    )

    let wallOffset = PauseCompactor.wallOffset(forActiveOffset: 15, pauses: [pause])
    #expect(wallOffset == 25)
    #expect(PauseCompactor.activeOffset(for: wallOffset, pauses: [pause]) == 15)
  }
}

