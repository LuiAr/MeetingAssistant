#if DEBUG
import Foundation

extension RecordingStore {
  /// Inserts a fake, completed recording with a long multi-speaker transcript so the
  /// transcript view can be previewed end-to-end (gutter, borders, wrapping, scrolling).
  ///
  /// DEBUG-only. Each call adds one new sample to the recordings directory; delete it from
  /// the sidebar (right-click → Delete) when you're done previewing.
  @discardableResult
  public func insertSampleLongRecording(segmentCount: Int = 240) throws -> RecordingMetadata {
    let id = UUID()
    let startedAt = Date()
    let folderName = "sample-long-\(id.uuidString.prefix(8))"

    // A pool of varied-length lines so the layout is exercised: short clauses, medium
    // sentences, and a couple of long ones that must wrap onto several lines.
    let lines = [
      "Thanks everyone for joining — let's get started.",
      "Quick recap from last week before we dive in.",
      "The migration finished overnight and all checks are green.",
      "I think we should prioritise the onboarding flow this sprint, because the drop-off numbers from the funnel review last month suggest most users never reach the second screen, and that's where the core value actually is.",
      "Agreed. Can we put a number on the expected lift?",
      "Roughly a fifteen to twenty percent improvement in activation, if the earlier A/B test holds.",
      "Let me share my screen.",
      "Can everyone see the dashboard?",
      "Yes, looks good on my end.",
      "One concern: the API latency spikes around peak hours and we haven't root-caused it yet, so before we promise anything to the customer we should probably add tracing to the slow path and confirm whether it's the database or the cache layer.",
      "I'll take the tracing task and report back Thursday.",
      "Perfect. What about the design review?",
      "Design is mostly signed off, just two small copy changes pending.",
      "Let's timebox the open questions to five minutes each.",
      "Action item: I'll send the updated spec by end of day.",
      "Any blockers on the release? No? Great.",
      "Let's circle back on pricing next week with finance in the room.",
      "Thanks all — I'll write up the notes and share them.",
    ]

    var segments: [TranscriptSegment] = []
    var clock: TimeInterval = 0
    for index in 0..<max(1, segmentCount) {
      let speaker: SpeakerLabel
      if index % 10 == 9 {
        speaker = .mixed
      } else {
        speaker = index.isMultiple(of: 2) ? .you : .computerAudio
      }
      let duration = TimeInterval(6 + (index % 7))
      segments.append(
        TranscriptSegment(
          startTime: clock,
          endTime: clock + duration,
          speaker: speaker,
          text: lines[index % lines.count],
          confidence: 0.9,
          isFinal: true
        )
      )
      clock += duration
    }

    let metadata = RecordingMetadata(
      id: id,
      title: "Sample — Long Transcript (DEBUG)",
      createdAt: startedAt,
      startedAt: startedAt,
      endedAt: startedAt.addingTimeInterval(clock),
      duration: clock,
      activeDuration: clock,
      localeIdentifier: Locale.current.identifier,
      folderName: folderName,
      systemAudioFileName: nil,
      microphoneAudioFileName: nil,
      mixedAudioFileName: nil,
      status: .completed
    )

    let document = RecordingDocument(metadata: metadata, pauses: [], transcript: segments)
    try persist(document)
    return metadata
  }
}
#endif
