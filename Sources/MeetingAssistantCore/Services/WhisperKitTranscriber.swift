import Foundation
import WhisperKit

public enum WhisperTranscriptionError: LocalizedError {
  case audioFileNotFound
  case modelDownloadFailed(String)
  case modelLoadFailed(String)
  case transcriptionFailed(String)

  public var errorDescription: String? {
    switch self {
    case .audioFileNotFound:
      return "The saved audio file could not be found."
    case .modelDownloadFailed(let detail):
      return "Could not download the Whisper model: \(detail)"
    case .modelLoadFailed(let detail):
      return "Could not load the Whisper model: \(detail)"
    case .transcriptionFailed(let detail):
      return "Transcription failed: \(detail)"
    }
  }
}

public struct WhisperTranscriptionProgress: Sendable, Equatable {
  public enum Phase: Sendable, Equatable {
    case downloadingModel(fraction: Double)
    case loadingModel
    case transcribing(fraction: Double)
  }

  public let phase: Phase
  public let modelName: String

  public init(phase: Phase, modelName: String) {
    self.phase = phase
    self.modelName = modelName
  }
}

public actor WhisperKitTranscriber {
  public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

  public typealias PipelineProvider = @Sendable () async throws -> WhisperKit

  private let modelName: String
  private let localeIdentifier: String
  private let progress: (@Sendable (WhisperTranscriptionProgress) -> Void)?
  private let pipelineProvider: PipelineProvider
  private var pipe: WhisperKit?

  public init(
    modelName: String = WhisperKitTranscriber.defaultModel,
    localeIdentifier: String,
    pipelineProvider: @escaping PipelineProvider,
    progress: (@Sendable (WhisperTranscriptionProgress) -> Void)? = nil
  ) {
    self.modelName = modelName
    self.localeIdentifier = localeIdentifier
    self.pipelineProvider = pipelineProvider
    self.progress = progress
  }

  public func prepare() async throws {
    if pipe != nil { return }
    progress?(.init(phase: .loadingModel, modelName: modelName))
    do {
      pipe = try await pipelineProvider()
    } catch let error as WhisperTranscriptionError {
      throw error
    } catch {
      throw WhisperTranscriptionError.modelLoadFailed(error.localizedDescription)
    }
  }

  public func transcribeAudioFile(url: URL, source: AudioSource) async throws -> [TranscriptSegment] {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw WhisperTranscriptionError.audioFileNotFound
    }

    try await prepare()
    guard let pipe else {
      throw WhisperTranscriptionError.modelLoadFailed("WhisperKit pipeline unavailable")
    }

    let model = self.modelName
    let progress = self.progress
    progress?(.init(phase: .transcribing(fraction: 0), modelName: model))

    let options = DecodingOptions(
      verbose: false,
      task: .transcribe,
      language: Self.whisperLanguageCode(from: localeIdentifier),
      temperature: 0.0,
      wordTimestamps: true,
      chunkingStrategy: .vad
    )

    let results: [TranscriptionResult]
    do {
      results = try await pipe.transcribe(
        audioPath: url.path,
        decodeOptions: options,
        callback: { update in
          progress?(.init(
            phase: .transcribing(fraction: Double(update.windowId) > 0 ? min(1.0, Double(update.windowId) / max(1.0, Double(update.windowId) + 1.0)) : 0),
            modelName: model
          ))
          return nil
        }
      )
    } catch {
      throw WhisperTranscriptionError.transcriptionFailed(error.localizedDescription)
    }

    progress?(.init(phase: .transcribing(fraction: 1.0), modelName: model))

    let allSegments = results.flatMap { $0.segments }
    return Self.mapToTranscriptSegments(allSegments, source: source)
  }

  static func mapToTranscriptSegments(
    _ segments: [TranscriptionSegment],
    source: AudioSource
  ) -> [TranscriptSegment] {
    let words = segments.flatMap { segment -> [WordWithConfidence] in
      if let wordTimings = segment.words, !wordTimings.isEmpty {
        return wordTimings.map { timing in
          WordWithConfidence(
            text: timing.word.trimmingCharacters(in: .whitespaces),
            start: TimeInterval(timing.start),
            end: TimeInterval(timing.end),
            confidence: Double(timing.probability)
          )
        }
      }
      let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return [] }
      return [
        WordWithConfidence(
          text: trimmed,
          start: TimeInterval(segment.start),
          end: TimeInterval(segment.end),
          confidence: min(1.0, max(0.0, Double(exp(segment.avgLogprob))))
        )
      ]
    }

    let cleaned = words.filter { !$0.text.isEmpty }
    guard !cleaned.isEmpty else { return [] }

    var grouped: [TranscriptSegment] = []
    var currentWords: [String] = []
    var currentStart: TimeInterval = 0
    var currentEnd: TimeInterval = 0
    var confidenceSum: Double = 0
    var confidenceCount = 0

    func flush() {
      let text = currentWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return }
      grouped.append(
        TranscriptSegment(
          startTime: currentStart,
          endTime: currentEnd,
          speaker: source.speakerLabel,
          text: text,
          confidence: confidenceCount > 0 ? confidenceSum / Double(confidenceCount) : nil,
          isFinal: true
        )
      )
      currentWords = []
      confidenceSum = 0
      confidenceCount = 0
    }

    for word in cleaned {
      let gap = word.start - currentEnd
      if !currentWords.isEmpty, gap > 1.2 || currentWords.count >= 24 {
        flush()
      }
      if currentWords.isEmpty {
        currentStart = word.start
      }
      currentWords.append(word.text)
      currentEnd = word.end
      confidenceSum += word.confidence
      confidenceCount += 1
    }

    flush()
    return grouped
  }

  static func whisperLanguageCode(from localeIdentifier: String) -> String {
    let locale = Locale(identifier: localeIdentifier)
    if let code = locale.language.languageCode?.identifier {
      return code
    }
    let base = localeIdentifier.components(separatedBy: CharacterSet(charactersIn: "_-@")).first ?? localeIdentifier
    return base.lowercased()
  }

  struct WordWithConfidence {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
  }
}
