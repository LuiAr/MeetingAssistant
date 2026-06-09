import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class RecordingStore {
  /// The default recordings location. The literal path now lives in the preferences
  /// abstraction so call sites that honour a user override resolve through it instead.
  nonisolated public static var defaultRootDirectory: URL {
    StorageLocationPreferences.defaultRecordingsDirectory
  }

  public private(set) var recordings: [RecordingMetadata] = []
  public private(set) var audioStorageBytes: Int64 = 0
  public private(set) var rootDirectory: URL
  /// Non-nil when the recordings folder could not be opened (for example its drive is not
  /// connected), so the UI can show a clear error and a way to re-pick the location.
  public private(set) var lastLoadError: String?

  private let fileManager: FileManager
  private let jsonEncoder: JSONEncoder
  private let jsonDecoder: JSONDecoder

  public init(rootDirectory: URL = StorageLocationPreferences.recordingsDirectory(), fileManager: FileManager = .default) {
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
      lastLoadError = nil
    } catch {
      recordings = []
      audioStorageBytes = 0
      lastLoadError = Self.unreachableMessage(for: rootDirectory)
      return
    }

    // Read and decode every recording.json off the main actor so a large library does not
    // block the UI while the library window opens or refreshes.
    let root = rootDirectory
    let documents = await Task.detached(priority: .utility) {
      Self.loadDocuments(in: root)
    }.value

    recordings = documents
      .map(\.metadata)
      .sorted { $0.startedAt > $1.startedAt }

    try? applyConfiguredAudioCleanupIfNeeded()
  }

  /// True when the recordings folder (or its containing folder) is reachable on disk. A custom
  /// folder on an external drive becomes unreachable when the drive is unplugged.
  public var isRootDirectoryReachable: Bool {
    if fileManager.fileExists(atPath: rootDirectory.path) { return true }
    let parent = rootDirectory.deletingLastPathComponent()
    return fileManager.fileExists(atPath: parent.path)
  }

  /// Changes where recordings are stored. When `moveExisting` is true, existing recording
  /// folders are moved into the new location; name collisions are skipped so nothing is ever
  /// overwritten. The in-memory list is reloaded from the new location afterwards.
  public func updateRootDirectory(to newURL: URL, moveExisting: Bool) async throws {
    let oldURL = rootDirectory
    guard oldURL.standardizedFileURL != newURL.standardizedFileURL else { return }

    try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)

    if moveExisting, fileManager.fileExists(atPath: oldURL.path) {
      try moveRecordingFolders(from: oldURL, to: newURL)
    }

    rootDirectory = newURL
    await reload()
  }

  private func moveRecordingFolders(from oldURL: URL, to newURL: URL) throws {
    let children = (try? fileManager.contentsOfDirectory(
      at: oldURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )) ?? []

    for child in children {
      let destination = newURL.appendingPathComponent(child.lastPathComponent)
      // Never overwrite: if the destination already exists, leave the source in place.
      guard !fileManager.fileExists(atPath: destination.path) else { continue }
      try fileManager.moveItem(at: child, to: destination)
    }
  }

  nonisolated static func unreachableMessage(for url: URL) -> String {
    "The recordings folder could not be opened at \(url.path). It may be on a drive that is not connected. Choose a new location in Settings ▸ Recordings."
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
    refreshAudioStorageBytes()
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

  public func audioURLs(for metadata: RecordingMetadata) -> [URL] {
    let directory = recordingDirectory(for: metadata)
    let fileNames = [
      metadata.mixedAudioFileName,
      metadata.systemAudioFileName,
      metadata.microphoneAudioFileName
    ]

    return fileNames.compactMap { fileName in
      guard let fileName else { return nil }
      let url = directory.appendingPathComponent(fileName)
      return fileManager.fileExists(atPath: url.path) ? url : nil
    }
  }

  public func revealAudioFiles(_ metadata: RecordingMetadata) {
    let urls = audioURLs(for: metadata)
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  public func hasAudioFiles(for metadata: RecordingMetadata) -> Bool {
    !audioURLs(for: metadata).isEmpty
  }

  public func applyConfiguredAudioCleanupIfNeeded(now: Date = Date()) throws {
    try applyAudioCleanup(
      policy: AudioStoragePreferences.policy(),
      storageLimitBytes: AudioStoragePreferences.storageLimitBytes(),
      now: now
    )
  }

  public func applyAudioCleanup(
    policy: AudioRetentionPolicy,
    storageLimitBytes: Int64 = Int64(AudioStoragePreferences.defaultStorageLimitBytes),
    now: Date = Date()
  ) throws {
    let documents = Self.loadDocuments(in: rootDirectory)

    switch policy {
    case .never:
      break
    case .after7Days, .after30Days, .after90Days:
      guard let days = policy.ageInDays,
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { break }
      for document in documents where cleanupDate(for: document.metadata) < cutoff {
        try deleteAudioFiles(for: document)
      }
    case .storageLimit:
      var remainingBytes = documents.reduce(Int64.zero) {
        $0 + audioStorageBytes(for: $1.metadata)
      }
      let limit = max(0, storageLimitBytes)
      let candidates = documents
        .filter { isEligibleForAudioCleanup($0.metadata) }
        .sorted(by: {
        cleanupDate(for: $0.metadata) < cleanupDate(for: $1.metadata)
      })
      for document in candidates where remainingBytes > limit {
        let bytes = audioStorageBytes(for: document.metadata)
        try deleteAudioFiles(for: document)
        remainingBytes -= bytes
      }
    }

    refreshAudioStorageBytes()
  }

  /// Renames a recording. Persisting rewrites both `recording.json` and the transcript
  /// Markdown (which embeds the title) and refreshes the in-memory list. The on-disk
  /// folder name is derived from the original date/id, so it intentionally does not change.
  public func rename(_ metadata: RecordingMetadata, to newTitle: String) throws {
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != metadata.title else { return }
    var document = try document(for: metadata)
    document.metadata.title = trimmed
    try persist(document)
  }

  /// Permanently deletes a recording's folder (audio + transcript + metadata) and removes
  /// it from the in-memory list.
  public func delete(_ metadata: RecordingMetadata) throws {
    let directory = recordingDirectory(for: metadata)
    if fileManager.fileExists(atPath: directory.path) {
      try fileManager.removeItem(at: directory)
    }
    recordings.removeAll { $0.id == metadata.id }
    refreshAudioStorageBytes()
  }

  private func ensureRootDirectory() throws {
    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
  }

  /// Reads and decodes every recording.json under `rootDirectory`. `nonisolated` and `static`
  /// so it can run off the main actor (see `reload()`); it uses its own decoder rather than
  /// the main-actor-isolated instance one. Unreadable or malformed entries are skipped.
  nonisolated static func loadDocuments(in rootDirectory: URL) -> [RecordingDocument] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: rootDirectory.path) else { return [] }
    guard let directories = try? fileManager.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return directories.compactMap { directory in
      let jsonURL = directory.appendingPathComponent("recording.json")
      guard let data = try? Data(contentsOf: jsonURL) else { return nil }
      return try? decoder.decode(RecordingDocument.self, from: data)
    }
  }

  private func deleteAudioFiles(for originalDocument: RecordingDocument) throws {
    guard isEligibleForAudioCleanup(originalDocument.metadata) else { return }
    var document = originalDocument

    for url in audioURLs(for: document.metadata) {
      try fileManager.removeItem(at: url)
    }

    document.metadata.systemAudioFileName = nil
    document.metadata.microphoneAudioFileName = nil
    document.metadata.mixedAudioFileName = nil
    try persist(document)
  }

  private func isEligibleForAudioCleanup(_ metadata: RecordingMetadata) -> Bool {
    switch metadata.status {
    case .recording, .paused, .requestingPermissions, .finalizing:
      return false
    case .idle, .completed, .failed:
      return true
    }
  }

  private func cleanupDate(for metadata: RecordingMetadata) -> Date {
    metadata.endedAt ?? metadata.startedAt
  }

  private func audioStorageBytes(for metadata: RecordingMetadata) -> Int64 {
    audioURLs(for: metadata).reduce(Int64.zero) { total, url in
      let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      return total + Int64(values?.fileSize ?? 0)
    }
  }

  private func refreshAudioStorageBytes() {
    audioStorageBytes = recordings.reduce(Int64.zero) {
      $0 + audioStorageBytes(for: $1)
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
