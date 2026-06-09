import CoreMedia
import Foundation
import ScreenCaptureKit

public struct CaptureOutputFiles: Equatable, Sendable {
  public var systemAudioURL: URL
  public var microphoneAudioURL: URL

  public init(systemAudioURL: URL, microphoneAudioURL: URL) {
    self.systemAudioURL = systemAudioURL
    self.microphoneAudioURL = microphoneAudioURL
  }
}

public final class SystemAudioCaptureService: NSObject {
  public typealias LevelHandler = @Sendable (AudioSource, Float) -> Void
  public typealias SampleHandler = @Sendable (AudioSource, CMSampleBuffer) -> Void
  public typealias WriteFailureHandler = @Sendable (AudioSource) -> Void

  private let sampleQueue = DispatchQueue(label: "MeetingAssistant.SystemAudioCaptureService.samples")
  private var stream: SCStream?
  private var systemWriter: CapturedAudioFileWriter?
  private var microphoneWriter: CapturedAudioFileWriter?
  private var onLevel: LevelHandler?
  private var onSample: SampleHandler?
  private var onWriteFailure: WriteFailureHandler?
  /// Sources for which a write failure has already been reported, so the handler fires once
  /// per source rather than on every dropped buffer. Only touched on `sampleQueue`.
  private var reportedWriteFailureSources: Set<AudioSource> = []
  private let pauseLock = NSLock()
  private var paused = false
  private var microphoneMuted = false

  public var isPaused: Bool {
    get {
      pauseLock.lock()
      defer { pauseLock.unlock() }
      return paused
    }
    set {
      pauseLock.lock()
      paused = newValue
      pauseLock.unlock()
    }
  }

  public var isMicrophoneMuted: Bool {
    get {
      pauseLock.lock()
      defer { pauseLock.unlock() }
      return microphoneMuted
    }
    set {
      pauseLock.lock()
      microphoneMuted = newValue
      pauseLock.unlock()
    }
  }

  public func startRecording(
    to directory: URL,
    microphoneDeviceID: String?,
    onLevel: @escaping LevelHandler,
    onSample: SampleHandler? = nil,
    onWriteFailure: WriteFailureHandler? = nil
  ) async throws -> CaptureOutputFiles {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let content = try await ScreenCaptureContentProvider.currentProcess()
    guard let display = content.displays.first else { throw CaptureServiceError.noDisplay }

    let filter = SCContentFilter(display: display, excludingWindows: [])

    let configuration = SCStreamConfiguration()
    configuration.width = 2
    configuration.height = 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    configuration.capturesAudio = true
    configuration.captureMicrophone = true
    configuration.excludesCurrentProcessAudio = true
    configuration.sampleRate = 48_000
    configuration.channelCount = 2
    configuration.showsCursor = false
    if let microphoneDeviceID, !microphoneDeviceID.isEmpty {
      configuration.microphoneCaptureDeviceID = microphoneDeviceID
    }

    let systemURL = directory.appendingPathComponent("system.caf")
    let microphoneURL = directory.appendingPathComponent("microphone.caf")

    // The writers and handlers are read on `sampleQueue` (the sample-handler queue) and
    // torn down from other threads (stopRecording, didStopWithError). Mutate them only on
    // `sampleQueue` so a sample buffer can never use a writer that is being closed/nilled,
    // which would race the non-thread-safe AVAudioFile underneath.
    let systemWriter = CapturedAudioFileWriter(url: systemURL)
    let microphoneWriter = CapturedAudioFileWriter(url: microphoneURL)
    sampleQueue.sync {
      self.systemWriter = systemWriter
      self.microphoneWriter = microphoneWriter
      self.onLevel = onLevel
      self.onSample = onSample
      self.onWriteFailure = onWriteFailure
      self.reportedWriteFailureSources = []
    }

    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
    try await start(stream)
    self.stream = stream
    return CaptureOutputFiles(systemAudioURL: systemURL, microphoneAudioURL: microphoneURL)
  }

  public func stopRecording() async {
    guard let stream else {
      closeWriters()
      return
    }

    _ = try? await stop(stream)
    self.stream = nil
    closeWriters()
  }

  /// Closes and releases the writers/handlers. Runs the teardown on `sampleQueue` (the same
  /// serial queue that delivers sample buffers) so it cannot overlap an in-flight write. Safe
  /// to call from `stopRecording()` and the `didStopWithError` delegate callback because
  /// neither runs on `sampleQueue`, so the `sync` hop cannot deadlock.
  private func closeWriters() {
    sampleQueue.sync {
      systemWriter?.close()
      microphoneWriter?.close()
      systemWriter = nil
      microphoneWriter = nil
      onLevel = nil
      onSample = nil
      onWriteFailure = nil
      reportedWriteFailureSources = []
    }
    isPaused = false
    isMicrophoneMuted = false
  }

  private func start(_ stream: SCStream) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      stream.startCapture { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func stop(_ stream: SCStream) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      stream.stopCapture { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}

extension SystemAudioCaptureService: SCStreamOutput, SCStreamDelegate {
  public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard sampleBuffer.isValid else { return }

    let source: AudioSource
    let writer: CapturedAudioFileWriter?
    switch type {
    case .audio:
      source = .system
      writer = systemWriter
    case .microphone:
      source = .microphone
      writer = microphoneWriter
    default:
      return
    }

    guard !isPaused else {
      onLevel?(source, 0)
      return
    }

    let muted = source == .microphone && isMicrophoneMuted

    do {
      let level = try writer?.write(sampleBuffer: sampleBuffer, muted: muted) ?? 0
      onLevel?(source, level)
      if !muted {
        onSample?(source, sampleBuffer)
      }
    } catch {
      onLevel?(source, 0)
      // Report the first write failure for this source so the UI can warn that capture is
      // incomplete. Subsequent failures for the same source are suppressed to avoid spamming.
      if reportedWriteFailureSources.insert(source).inserted {
        onWriteFailure?(source)
      }
    }
  }

  public func stream(_ stream: SCStream, didStopWithError error: Error) {
    closeWriters()
  }
}
