import Foundation

public struct RecordingMetadata: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var createdAt: Date
  public var startedAt: Date
  public var endedAt: Date?
  public var duration: TimeInterval
  public var activeDuration: TimeInterval
  public var localeIdentifier: String
  public var folderName: String
  public var transcriptFileName: String
  public var systemAudioFileName: String?
  public var microphoneAudioFileName: String?
  public var mixedAudioFileName: String?
  public var status: RecordingStatus
  public var errorMessage: String?

  public init(
    id: UUID = UUID(),
    title: String,
    createdAt: Date = Date(),
    startedAt: Date,
    endedAt: Date? = nil,
    duration: TimeInterval = 0,
    activeDuration: TimeInterval = 0,
    localeIdentifier: String = Locale.current.identifier,
    folderName: String,
    transcriptFileName: String = "transcript.md",
    systemAudioFileName: String? = "system.caf",
    microphoneAudioFileName: String? = "microphone.caf",
    mixedAudioFileName: String? = nil,
    status: RecordingStatus = .idle,
    errorMessage: String? = nil
  ) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.duration = duration
    self.activeDuration = activeDuration
    self.localeIdentifier = localeIdentifier
    self.folderName = folderName
    self.transcriptFileName = transcriptFileName
    self.systemAudioFileName = systemAudioFileName
    self.microphoneAudioFileName = microphoneAudioFileName
    self.mixedAudioFileName = mixedAudioFileName
    self.status = status
    self.errorMessage = errorMessage
  }
}

