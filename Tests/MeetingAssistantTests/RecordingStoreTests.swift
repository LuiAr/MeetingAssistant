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

  @Test
  @MainActor
  func prefersMixedAudioWhenListingFiles() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = RecordingStore(rootDirectory: root)
    var document = try store.createDraft(
      title: "Audio Files",
      localeIdentifier: "en_US",
      startedAt: Date(timeIntervalSince1970: 2_000)
    )
    document.metadata.status = .completed
    document.metadata.mixedAudioFileName = "mixed.caf"
    try writeAudioFiles(for: document.metadata, in: store, sizes: [
      "system.caf": 2,
      "microphone.caf": 3,
      "mixed.caf": 4
    ])
    try store.persist(document)

    #expect(store.audioURLs(for: document.metadata).map(\.lastPathComponent) == [
      "mixed.caf",
      "system.caf",
      "microphone.caf"
    ])
    #expect(store.audioStorageBytes == 9)
  }

  @Test
  @MainActor
  func ageCleanupDeletesOnlyAudioAndPreservesTranscript() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = RecordingStore(rootDirectory: root)
    let startedAt = Date(timeIntervalSince1970: 2_000)
    var document = try store.createDraft(title: "Old Meeting", localeIdentifier: "en_US", startedAt: startedAt)
    document.metadata.endedAt = startedAt.addingTimeInterval(60)
    document.metadata.status = .completed
    document.transcript = [
      TranscriptSegment(startTime: 0, speaker: .you, text: "Keep this transcript.")
    ]
    try writeAudioFiles(for: document.metadata, in: store, sizes: [
      "system.caf": 5,
      "microphone.caf": 5
    ])
    try store.persist(document)

    try store.applyAudioCleanup(
      policy: .after7Days,
      now: startedAt.addingTimeInterval(8 * 24 * 60 * 60)
    )

    let cleaned = try store.document(for: document.metadata)
    #expect(cleaned.metadata.systemAudioFileName == nil)
    #expect(cleaned.metadata.microphoneAudioFileName == nil)
    #expect(store.audioURLs(for: cleaned.metadata).isEmpty)
    #expect(store.transcriptText(for: cleaned.metadata).contains("Keep this transcript."))
    #expect(FileManager.default.fileExists(atPath: store.transcriptURL(for: cleaned.metadata).path))
    #expect(store.audioStorageBytes == 0)
  }

  @Test
  @MainActor
  func storageLimitCleanupDeletesOldestAudioFirst() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = RecordingStore(rootDirectory: root)
    let old = try completedDocument(
      title: "Old",
      startedAt: Date(timeIntervalSince1970: 2_000),
      audioBytes: 8,
      store: store
    )
    let recent = try completedDocument(
      title: "Recent",
      startedAt: Date(timeIntervalSince1970: 4_000),
      audioBytes: 8,
      store: store
    )

    try store.applyAudioCleanup(policy: .storageLimit, storageLimitBytes: 10)

    #expect(store.audioURLs(for: old.metadata).isEmpty)
    #expect(store.audioURLs(for: recent.metadata).map(\.lastPathComponent) == ["system.caf"])
    #expect(store.audioStorageBytes == 8)
  }

  @Test
  @MainActor
  func updateRootDirectoryMovesExistingRecordings() async throws {
    let rootA = temporaryRoot()
    let rootB = temporaryRoot()
    defer {
      try? FileManager.default.removeItem(at: rootA)
      try? FileManager.default.removeItem(at: rootB)
    }

    let store = RecordingStore(rootDirectory: rootA)
    var document = try store.createDraft(
      title: "Movable",
      localeIdentifier: "en_US",
      startedAt: Date(timeIntervalSince1970: 2_000)
    )
    document.metadata.status = .completed
    try store.persist(document)
    let folderName = document.metadata.folderName

    try await store.updateRootDirectory(to: rootB, moveExisting: true)

    #expect(store.rootDirectory.standardizedFileURL == rootB.standardizedFileURL)
    #expect(store.recordings.count == 1)
    #expect(store.recordings.first?.title == "Movable")
    #expect(FileManager.default.fileExists(atPath: rootB.appendingPathComponent(folderName).path))
    #expect(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(folderName).path) == false)
  }

  @Test
  @MainActor
  func updateRootDirectoryWithoutMovingLeavesExistingInPlace() async throws {
    let rootA = temporaryRoot()
    let rootB = temporaryRoot()
    defer {
      try? FileManager.default.removeItem(at: rootA)
      try? FileManager.default.removeItem(at: rootB)
    }

    let store = RecordingStore(rootDirectory: rootA)
    var document = try store.createDraft(
      title: "Stays",
      localeIdentifier: "en_US",
      startedAt: Date(timeIntervalSince1970: 2_000)
    )
    document.metadata.status = .completed
    try store.persist(document)
    let folderName = document.metadata.folderName

    try await store.updateRootDirectory(to: rootB, moveExisting: false)

    #expect(store.rootDirectory.standardizedFileURL == rootB.standardizedFileURL)
    #expect(store.recordings.isEmpty)
    #expect(FileManager.default.fileExists(atPath: rootA.appendingPathComponent(folderName).path))
  }

  @MainActor
  private func completedDocument(
    title: String,
    startedAt: Date,
    audioBytes: Int,
    store: RecordingStore
  ) throws -> RecordingDocument {
    var document = try store.createDraft(title: title, localeIdentifier: "en_US", startedAt: startedAt)
    document.metadata.status = .completed
    document.metadata.endedAt = startedAt.addingTimeInterval(60)
    document.metadata.microphoneAudioFileName = nil
    try writeAudioFiles(for: document.metadata, in: store, sizes: ["system.caf": audioBytes])
    try store.persist(document)
    return document
  }

  @MainActor
  private func writeAudioFiles(
    for metadata: RecordingMetadata,
    in store: RecordingStore,
    sizes: [String: Int]
  ) throws {
    let directory = store.recordingDirectory(for: metadata)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (fileName, size) in sizes {
      try Data(repeating: 1, count: size).write(to: directory.appendingPathComponent(fileName))
    }
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("MeetingAssistantTests-\(UUID().uuidString)", isDirectory: true)
  }
}
