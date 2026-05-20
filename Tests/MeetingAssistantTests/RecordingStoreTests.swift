import Foundation
import Testing
@testable import MeetingAssistantCore

@Suite("RecordingStore")
struct RecordingStoreTests {
  @Test
  @MainActor
  func persistsReloadsAndReadsTranscript() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MeetingAssistantTests-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: root)
    }

    let store = RecordingStore(rootDirectory: root)
    let startedAt = Date(timeIntervalSince1970: 2_000)
    var document = try store.createDraft(title: "Design Review", localeIdentifier: "en_US", startedAt: startedAt)
    document.metadata.endedAt = startedAt.addingTimeInterval(30)
    document.metadata.duration = 30
    document.metadata.activeDuration = 30
    document.metadata.status = .completed
    document.transcript = [
      TranscriptSegment(startTime: 5, speaker: .you, text: "Let's start.")
    ]

    try store.persist(document)
    await store.reload()

    #expect(store.recordings.count == 1)
    #expect(store.recordings.first?.title == "Design Review")
    #expect(store.transcriptText(for: document.metadata).contains("[00:00:05] You: Let's start."))
  }
}

