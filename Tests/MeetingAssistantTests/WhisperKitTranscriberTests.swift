import Testing
import Foundation
import WhisperKit
@testable import MeetingAssistantCore

@Suite("WhisperKitTranscriber")
struct WhisperKitTranscriberTests {
  @Test
  func normalizesLocaleIdentifierToWhisperLanguageCode() {
    #expect(WhisperKitTranscriber.whisperLanguageCode(from: "en_US") == "en")
    #expect(WhisperKitTranscriber.whisperLanguageCode(from: "en-US") == "en")
    #expect(WhisperKitTranscriber.whisperLanguageCode(from: "fr_FR@calendar=gregorian") == "fr")
    #expect(WhisperKitTranscriber.whisperLanguageCode(from: "sv") == "sv")
  }

  @Test
  func groupsWordsByGapAndLength() {
    let segments = [
      makeSegment(
        start: 0,
        end: 2.0,
        words: [
          ("Hello", 0.0, 0.4, 0.95),
          ("world", 0.5, 1.0, 0.92),
        ]
      ),
      makeSegment(
        start: 4.0,
        end: 5.0,
        words: [
          ("after", 4.0, 4.3, 0.9),
          ("gap", 4.4, 4.7, 0.88),
        ]
      ),
    ]

    let result = WhisperKitTranscriber.mapToTranscriptSegments(segments, source: .microphone)

    #expect(result.count == 2)
    #expect(result[0].text == "Hello world")
    #expect(result[0].speaker == .you)
    #expect(result[1].text == "after gap")
    #expect(result[1].startTime == 4.0)
  }

  @Test
  func flushesAfter24Words() {
    let words = (0..<30).map { i in
      ("w\(i)", Float(i) * 0.1, Float(i) * 0.1 + 0.05, Float(0.9))
    }
    let segment = makeSegment(start: 0, end: words.last!.1 + 0.1, words: words)

    let result = WhisperKitTranscriber.mapToTranscriptSegments([segment], source: .system)

    #expect(result.count == 2)
    #expect(result[0].speaker == .computerAudio)
    #expect(result[0].text.split(separator: " ").count == 24)
    #expect(result[1].text.split(separator: " ").count == 6)
  }

  @Test
  func fallsBackToSegmentTextWhenNoWordTimings() {
    let segment = TranscriptionSegment(
      id: 0,
      seek: 0,
      start: 1.0,
      end: 3.0,
      text: " Plain segment text. ",
      tokens: [],
      tokenLogProbs: [],
      temperature: 0,
      avgLogprob: -0.2,
      compressionRatio: 1.0,
      noSpeechProb: 0.0,
      words: nil
    )

    let result = WhisperKitTranscriber.mapToTranscriptSegments([segment], source: .system)

    #expect(result.count == 1)
    #expect(result[0].text == "Plain segment text.")
    #expect(result[0].startTime == 1.0)
    #expect(result[0].endTime == 3.0)
  }

  @Test
  func stripsWhisperSpecialTokens() {
    let segment = makeSegment(
      start: 0,
      end: 1.0,
      words: [
        ("<|startoftranscript|>", 0.0, 0.0, 0.5),
        ("<|en|>", 0.0, 0.0, 0.5),
        ("Hello", 0.1, 0.4, 0.95),
        ("there", 0.5, 0.8, 0.93),
        ("<|endoftext|>", 0.9, 0.9, 0.5),
      ]
    )

    let result = WhisperKitTranscriber.mapToTranscriptSegments([segment], source: .system)

    #expect(result.count == 1)
    #expect(result[0].text == "Hello there")
  }

  private func makeSegment(
    start: Float,
    end: Float,
    words: [(String, Float, Float, Float)]
  ) -> TranscriptionSegment {
    TranscriptionSegment(
      id: 0,
      seek: 0,
      start: start,
      end: end,
      text: words.map(\.0).joined(separator: " "),
      tokens: [],
      tokenLogProbs: [],
      temperature: 0,
      avgLogprob: -0.1,
      compressionRatio: 1.0,
      noSpeechProb: 0.0,
      words: words.map { (text, s, e, p) in
        WordTiming(word: text, tokens: [], start: s, end: e, probability: p)
      }
    )
  }
}
