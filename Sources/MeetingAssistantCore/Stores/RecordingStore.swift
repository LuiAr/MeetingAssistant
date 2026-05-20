import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class RecordingStore {
  nonisolated public static var defaultRootDirectory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeetingAssistant Recordings", isDirectory: true)
  }

  public private(set) var recordings: [RecordingMetadata] = []
  public var rootDirectory: URL

  private let fileManager: FileManager
  private let jsonEncoder: JSONEncoder
  private let jsonDecoder: JSONDecoder

  public init(rootDirectory: URL = RecordingStore.defaultRootDirectory, fileManager: FileManager = .default) {
    self.rootDirectory = rootDirectory
    self.fileManager = fileManager

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.jsonEncoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.jsonDecoder = decoder
  }

  public func reload() async {
    do {
      try ensureRootDirectory()
      let documents = try loadDocuments()
      recordings = documents
        .map(\.metadata)
        .sorted { $0.startedAt > $1.startedAt }
    } catch {
      recordings = []
    }
  }

  public func createDraft(title: String, localeIdentifier: String, startedAt: Date = Date()) throws -> RecordingDocument {
    try ensureRootDirectory()
    let id = UUID()
    let folderName = Self.folderName(for: startedAt, id: id)
    let metadata = RecordingMetadata(
      id: id,
      title: title,
      createdAt: startedAt,
      startedAt: startedAt,
      localeIdentifier: localeIdentifier,
      folderName: folderName,
      status: .recording
    )
    let document = RecordingDocument(metadata: metadata)
    try persist(document)
    return document
  }

  public func persist(_ document: RecordingDocument) throws {
    try ensureRootDirectory()
    let directory = recordingDirectory(for: document.metadata)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let jsonURL = directory.appendingPathComponent("recording.json")
    let data = try jsonEncoder.encode(document)
    try data.write(to: jsonURL, options: [.atomic])

    let transcriptURL = directory.appendingPathComponent(document.metadata.transcriptFileName)
    let markdown = MarkdownExporter.markdown(for: document)
    try markdown.write(to: transcriptURL, atomically: true, encoding: .utf8)

    upsert(document.metadata)
  }

  public func document(for metadata: RecordingMetadata) throws -> RecordingDocument {
    let data = try Data(contentsOf: recordingDirectory(for: metadata).appendingPathComponent("recording.json"))
    return try jsonDecoder.decode(RecordingDocument.self, from: data)
  }

  public func transcriptText(for metadata: RecordingMetadata) -> String {
    let url = recordingDirectory(for: metadata).appendingPathComponent(metadata.transcriptFileName)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }

  public func recordingDirectory(for metadata: RecordingMetadata) -> URL {
    rootDirectory.appendingPathComponent(metadata.folderName, isDirectory: true)
  }

  public func transcriptURL(for metadata: RecordingMetadata) -> URL {
    recordingDirectory(for: metadata).appendingPathComponent(metadata.transcriptFileName)
  }

  public func revealInFinder(_ metadata: RecordingMetadata) {
    NSWorkspace.shared.activateFileViewerSelecting([transcriptURL(for: metadata)])
  }

  private func ensureRootDirectory() throws {
    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
  }

  private func loadDocuments() throws -> [RecordingDocument] {
    guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
    let directories = try fileManager.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    return directories.compactMap { directory in
      let jsonURL = directory.appendingPathComponent("recording.json")
      guard let data = try? Data(contentsOf: jsonURL) else { return nil }
      return try? jsonDecoder.decode(RecordingDocument.self, from: data)
    }
  }

  private func upsert(_ metadata: RecordingMetadata) {
    recordings.removeAll { $0.id == metadata.id }
    recordings.append(metadata)
    recordings.sort { $0.startedAt > $1.startedAt }
  }

  private static func folderName(for date: Date, id: UUID) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "\(formatter.string(from: date))-\(id.uuidString.prefix(8))"
  }
}
