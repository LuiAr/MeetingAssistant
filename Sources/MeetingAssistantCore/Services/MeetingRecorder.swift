import Foundation
import Observation

@MainActor
@Observable
public final class MeetingRecorder {
  public private(set) var status: RecordingStatus = .idle
  public private(set) var elapsed: TimeInterval = 0
  public private(set) var activeElapsed: TimeInterval = 0
  public private(set) var levels = AudioLevelSnapshot()
  public private(set) var liveTranscript: [TranscriptSegment] = []
  public private(set) var isMicrophoneMuted = false
  public private(set) var currentDocument: RecordingDocument?
  public private(set) var errorMessage: String?
  public private(set) var transcriptionProgress: WhisperTranscriptionProgress?

  public let permissions = PermissionCenter()

  private let store: RecordingStore
  private let modelManager: ModelDownloadManager
  private var stateMachine = RecordingStateMachine()
  private var captureService: SystemAudioCaptureService?
  private var timerTask: Task<Void, Never>?

  public init(store: RecordingStore, modelManager: ModelDownloadManager? = nil) {
    self.store = store
    self.modelManager = modelManager ?? .shared
  }

  public func startRecording(title: String, localeIdentifier: String, microphoneDeviceID: String?) async {
    guard status == .idle || status == .completed || status == .failed else { return }

    guard modelManager.isModelOnDisk() else {
      stateMachine.fail("The Whisper model has not been downloaded yet. Open Settings to download it before recording.")
      publishState()
      return
    }

    stateMachine.requestPermissions()
    publishState()

    guard await permissions.requestRequiredPermissions() else {
      stateMachine.fail("Microphone and Screen Recording permissions are required before recording.")
      publishState()
      return
    }

    let startedAt = Date()
    let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? Self.defaultTitle(for: startedAt)
      : title.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      var document = try store.createDraft(title: resolvedTitle, localeIdentifier: localeIdentifier, startedAt: startedAt)
      currentDocument = document
      liveTranscript = []
      isMicrophoneMuted = false
      levels = AudioLevelSnapshot()
      errorMessage = nil
      stateMachine.start(at: startedAt)
      publishState()

      let captureService = SystemAudioCaptureService()
      let directory = store.recordingDirectory(for: document.metadata)
      let outputFiles = try await captureService.startRecording(
        to: directory,
        microphoneDeviceID: microphoneDeviceID,
        onLevel: { [weak self] source, level in
          Task { @MainActor [weak self] in
            self?.levels.set(level, for: source)
          }
        }
      )

      document.metadata.systemAudioFileName = outputFiles.systemAudioURL.lastPathComponent
      document.metadata.microphoneAudioFileName = outputFiles.microphoneAudioURL.lastPathComponent
      currentDocument = document
      try store.persist(document)

      self.captureService = captureService
      startTimer()
    } catch {
      stateMachine.fail(error.localizedDescription)
      errorMessage = error.localizedDescription
      if var document = currentDocument {
        document.metadata.status = .failed
        document.metadata.errorMessage = error.localizedDescription
        try? store.persist(document)
      }
      publishState()
    }
  }

  public func pause() {
    guard status == .recording else { return }
    captureService?.isPaused = true
    stateMachine.pause(at: Date())
    publishState()
  }

  public func resume() {
    guard status == .paused else { return }
    stateMachine.resume(at: Date())
    captureService?.isPaused = false
    if var document = currentDocument {
      document.pauses = stateMachine.pauses
      currentDocument = document
    }
    publishState()
  }

  /// Mutes or unmutes the microphone mid-recording. Muted audio is written to the mic track
  /// as silence (preserving the timeline) so it is not transcribed.
  public func setMicrophoneMuted(_ muted: Bool) {
    guard status == .recording || status == .paused else { return }
    isMicrophoneMuted = muted
    captureService?.isMicrophoneMuted = muted
  }

  public func stop() async {
    guard status == .recording || status == .paused else { return }

    if status == .paused {
      stateMachine.resume(at: Date())
    }
    stateMachine.finalize()
    publishState()
    timerTask?.cancel()
    timerTask = nil

    await captureService?.stopRecording()

    let endedAt = Date()
    guard var document = currentDocument else {
      resetAfterStop()
      return
    }

    let transcript = await finalTranscript(for: document, pauses: stateMachine.pauses)
    document.pauses = stateMachine.pauses
    document.transcript = transcript.isEmpty ? unavailableTranscriptSegment() : transcript
    document.metadata.endedAt = endedAt
    document.metadata.duration = stateMachine.wallElapsed(at: endedAt)
    document.metadata.activeDuration = stateMachine.activeElapsed(at: endedAt)
    document.metadata.status = .completed

    do {
      try store.persist(document)
      currentDocument = document
      stateMachine.complete()
      publishState()
      try? store.applyConfiguredAudioCleanupIfNeeded()
    } catch {
      stateMachine.fail(error.localizedDescription)
      errorMessage = error.localizedDescription
      publishState()
    }

    resetAfterStop(keepDocument: true)
  }

  public func discardCurrentError() {
    errorMessage = nil
    if status == .failed {
      status = .idle
      stateMachine = RecordingStateMachine()
    }
  }

  private func publishState() {
    status = stateMachine.status
    errorMessage = stateMachine.errorMessage
    let now = Date()
    elapsed = stateMachine.wallElapsed(at: now)
    activeElapsed = stateMachine.activeElapsed(at: now)
  }

  private func startTimer() {
    timerTask?.cancel()
    timerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard let self else { break }
        await MainActor.run {
          self.publishState()
        }
      }
    }
  }

  private func expandTranscriptForPersistence(_ transcript: [TranscriptSegment], pauses: [PauseInterval]) -> [TranscriptSegment] {
    transcript.map { segment in
      var expanded = segment
      expanded.startTime = PauseCompactor.wallOffset(forActiveOffset: segment.startTime, pauses: pauses)
      if let endTime = segment.endTime {
        expanded.endTime = PauseCompactor.wallOffset(forActiveOffset: endTime, pauses: pauses)
      }
      return expanded
    }
  }

  private func finalTranscript(for document: RecordingDocument, pauses: [PauseInterval]) async -> [TranscriptSegment] {
    let manager = modelManager
    let transcriber = WhisperKitTranscriber(
      localeIdentifier: document.metadata.localeIdentifier,
      pipelineProvider: { @Sendable in
        try await manager.ensureReady()
      },
      progress: { [weak self] update in
        Task { @MainActor [weak self] in
          self?.transcriptionProgress = update
        }
      }
    )
    let directory = store.recordingDirectory(for: document.metadata)
    var segments: [TranscriptSegment] = []
    var errors: [String] = []

    if let systemAudioFileName = document.metadata.systemAudioFileName {
      let url = directory.appendingPathComponent(systemAudioFileName)
      do {
        segments.append(contentsOf: try await transcriber.transcribeAudioFile(url: url, source: .system))
      } catch {
        errors.append("Computer audio: \(error.localizedDescription)")
      }
    }

    if let microphoneAudioFileName = document.metadata.microphoneAudioFileName {
      let url = directory.appendingPathComponent(microphoneAudioFileName)
      do {
        segments.append(contentsOf: try await transcriber.transcribeAudioFile(url: url, source: .microphone))
      } catch {
        errors.append("Microphone: \(error.localizedDescription)")
      }
    }

    transcriptionProgress = nil

    let expandedSegments = expandTranscriptForPersistence(
      segments.sorted { $0.startTime < $1.startTime },
      pauses: pauses
    )

    var finalSegments = expandedSegments
    if !errors.isEmpty {
      finalSegments.append(
        TranscriptSegment(
          startTime: document.metadata.activeDuration,
          speaker: .mixed,
          text: "[System Warning: \(errors.joined(separator: " "))]",
          isFinal: true
        )
      )
    }

    guard expandedSegments.isEmpty, !errors.isEmpty else {
      return finalSegments
    }

    return [
      TranscriptSegment(
        startTime: 0,
        speaker: .mixed,
        text: "Transcription unavailable. \(errors.joined(separator: " "))",
        isFinal: true
      )
    ]
  }

  private func unavailableTranscriptSegment() -> [TranscriptSegment] {
    [
      TranscriptSegment(
        startTime: 0,
        speaker: .mixed,
        text: "No transcript was produced. The audio files were saved and can be retried after the Whisper model has been downloaded.",
        isFinal: true
      )
    ]
  }

  private func resetAfterStop(keepDocument: Bool = false) {
    captureService = nil
    levels = AudioLevelSnapshot()
    isMicrophoneMuted = false
    if !keepDocument {
      currentDocument = nil
      liveTranscript = []
    }
  }

  private static func defaultTitle(for date: Date) -> String {
    "Meeting \(date.formatted(date: .abbreviated, time: .shortened))"
  }
}
