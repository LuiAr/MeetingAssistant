import Foundation
import Testing
@testable import MeetingAssistantCore

@Suite("MarkdownExporter")
struct MarkdownExporterTests {
  @Test
  func includesMetadataPausesFilesAndTimecodedTranscript() {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    let pause = PauseInterval(
      startedAt: startedAt.addingTimeInterval(30),
      endedAt: startedAt.addingTimeInterval(45),
      startOffset: 30,
      endOffset: 45
    )
    let metadata = RecordingMetadata(
      id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      title: "Planning",
      createdAt: startedAt,
      startedAt: startedAt,
      endedAt: startedAt.addingTimeInterval(90),
      duration: 90,
      activeDuration: 75,
      localeIdentifier: "en_US",
      folderName: "planning"
    )
    let document = RecordingDocument(
      metadata: metadata,
      pauses: [pause],
      transcript: [
        TranscriptSegment(startTime: 50, speaker: .computerAudio, text: "Roadmap looks good.")
      ]
    )

    let markdown = MarkdownExporter.markdown(for: document)

    #expect(markdown.contains("# Planning"))
    #expect(markdown.contains("- Computer audio: `system.caf`"))
    #expect(markdown.contains("- Microphone: `microphone.caf`"))
    #expect(markdown.contains("- 00:00:30-00:00:45"))
    #expect(markdown.contains("[00:00:35] Computer audio: Roadmap looks good."))
  }
}

