import AppKit
import Foundation
import MeetingAssistantCore

/// Serialises all writes to stdout as NDJSON. Safe to call from any thread (the MainActor
/// command handlers and background emitters both write through it).
final class SidecarIO: @unchecked Sendable {
  private let lock = NSLock()

  func writeObject(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    lock.lock()
    defer { lock.unlock() }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
  }

  func emit(_ object: [String: Any]) {
    writeObject(object)
  }

  func emitReady() {
    writeObject([
      "event": "ready",
      "protocol": protocolVersion,
      "sidecar": sidecarVersion,
      "pid": Int(ProcessInfo.processInfo.processIdentifier),
      "bundleId": Bundle.main.bundleIdentifier ?? sidecarBundleIdentifier
    ])
  }

  func respond(id: String, result: [String: Any]) {
    writeObject(["id": id, "ok": true, "result": result])
  }

  func respondError(id: String, code: String, message: String) {
    writeObject(["id": id, "ok": false, "error": ["code": code, "message": message]])
  }

  func emitError(scope: String, code: String, message: String) {
    writeObject(["event": "error", "scope": scope, "code": code, "message": message])
  }

  func log(_ message: String) {
    FileHandle.standardError.write(Data("[sidecar] \(message)\n".utf8))
  }
}

/// Encodes the core's Codable types into JSON dictionaries using the same conventions as the
/// on-disk format (ISO8601 dates), so responses and recording.json never disagree on shape.
enum JSONCoding {
  static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    let decoded = try JSONSerialization.jsonObject(with: data)
    return decoded as? [String: Any] ?? [:]
  }
}

/// Owns the reused headless core (recorder, store, model manager) and routes the full frozen
/// command surface. This is the plan's Phase 3 "headless core": the command/event loop lives
/// here in the sidecar and the root package stays untouched, with the unused SwiftUI views
/// simply never instantiated.
@MainActor
final class SidecarController {
  private let io: SidecarIO
  private let store: RecordingStore
  private let recorder: MeetingRecorder
  private let modelManager: ModelDownloadManager
  private var pollTask: Task<Void, Never>?

  private var lastStatus: RecordingStatus?
  private var lastLevels = AudioLevelSnapshot()
  private var lastTranscriptionProgress: WhisperTranscriptionProgress?
  private var lastModelStatus: ModelStatus?

  init(io: SidecarIO) {
    self.io = io
    self.modelManager = ModelDownloadManager.shared
    let store = RecordingStore()
    self.store = store
    self.recorder = MeetingRecorder(store: store, modelManager: ModelDownloadManager.shared)
    startStatePolling()
  }

  /// Runs each command in its own MainActor task so a long-running command (stop with
  /// transcription, a model download) does not block the stdin command loop. Responses
  /// carry the caller's id, so ordering across concurrent commands is not guaranteed.
  func dispatch(_ command: IncomingCommand) {
    Task { @MainActor in
      await self.handle(command)
    }
  }

  func handle(_ command: IncomingCommand) async {
    do {
      switch command.cmd {
      case "permissions.status":
        handlePermissionsStatus(command)
      case "permissions.request":
        await handlePermissionsRequest(command)
      case "record.start":
        try await handleRecordStart(command)
      case "record.pause":
        try handleRecordPause(command)
      case "record.resume":
        try handleRecordResume(command)
      case "record.muteMic":
        try handleRecordMuteMic(command)
      case "record.stop":
        try await handleRecordStop(command)
      case "model.status":
        handleModelStatus(command)
      case "model.download":
        try handleModelDownload(command)
      case "model.setLocation":
        try await handleModelSetLocation(command)
      case "library.list":
        try await handleLibraryList(command)
      case "library.document":
        try await handleLibraryDocument(command)
      case "library.rename":
        try await handleLibraryRename(command)
      case "library.delete":
        try await handleLibraryDelete(command)
      case "library.revealAudio":
        try await handleLibraryRevealAudio(command)
      case "export.markdown":
        try await handleExportMarkdown(command)
      case "export.aiContext":
        try await handleExportAIContext(command)
      case "storage.setRecordingsRoot":
        try await handleStorageSetRecordingsRoot(command)
      case "storage.usage":
        await handleStorageUsage(command)
      case "storage.setRetention":
        try handleStorageSetRetention(command)
      case "storage.applyRetention":
        try await handleStorageApplyRetention(command)
      default:
        throw SidecarError.message(
          code: "unsupportedCommand",
          text: "Command \"\(command.cmd)\" is not part of the sidecar contract."
        )
      }
    } catch let SidecarError.message(code, text) {
      io.respondError(id: command.id, code: code, message: text)
    } catch {
      io.respondError(id: command.id, code: "internal", message: error.localizedDescription)
    }
  }

  // MARK: - State polling (status, levels, transcription progress, model status)

  private func startStatePolling() {
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(120))
        guard let self else { break }
        self.emitStateChanges()
      }
    }
  }

  private func emitStateChanges() {
    let status = recorder.status
    if status != lastStatus {
      lastStatus = status
      io.emit(["event": "status", "value": status.rawValue])
    }

    let levels = recorder.levels
    if (status == .recording || status == .paused), levels != lastLevels {
      lastLevels = levels
      io.emit(["event": "levels", "mic": levels.microphone, "system": levels.system])
    }

    let progress = recorder.transcriptionProgress
    if progress != lastTranscriptionProgress {
      lastTranscriptionProgress = progress
      if let progress {
        io.emit(transcriptionProgressPayload(progress))
      }
    }

    let modelStatus = modelManager.status
    if modelStatus != lastModelStatus {
      lastModelStatus = modelStatus
      var payload = modelStatusFields(modelStatus)
      payload["event"] = "model.status"
      io.emit(payload)
    }
  }

  private func transcriptionProgressPayload(_ progress: WhisperTranscriptionProgress) -> [String: Any] {
    var payload: [String: Any] = [
      "event": "transcription.progress",
      "model": progress.modelName
    ]
    switch progress.phase {
    case .downloadingModel(let fraction):
      payload["phase"] = "download"
      payload["fraction"] = fraction
    case .loadingModel:
      payload["phase"] = "load"
    case .transcribing(let fraction):
      payload["phase"] = "transcribe"
      payload["fraction"] = fraction
    }
    return payload
  }

  private func modelStatusFields(_ status: ModelStatus) -> [String: Any] {
    var fields: [String: Any] = [:]
    switch status {
    case .unknown:
      fields["value"] = "unknown"
    case .notDownloaded:
      fields["value"] = "notDownloaded"
    case .downloading(let fraction, let attempt):
      fields["value"] = "downloading"
      fields["fraction"] = fraction
      fields["attempt"] = attempt
    case .waitingForNetwork(let attempt):
      fields["value"] = "waitingForNetwork"
      fields["attempt"] = attempt
    case .downloaded:
      fields["value"] = "downloaded"
    case .loading:
      fields["value"] = "loading"
    case .ready:
      fields["value"] = "ready"
    case .failed(let message):
      fields["value"] = "failed"
      fields["message"] = message
    }
    return fields
  }

  // MARK: - Permissions

  private func handlePermissionsStatus(_ command: IncomingCommand) {
    recorder.permissions.refreshCachedStatuses()
    io.respond(id: command.id, result: [
      "microphone": recorder.permissions.microphone.rawValue,
      "screen": recorder.permissions.systemAudio.rawValue
    ])
  }

  private func handlePermissionsRequest(_ command: IncomingCommand) async {
    let kinds = command.kinds ?? ["microphone", "screen"]
    let result: PermissionRequestResult
    if kinds.contains("screen") {
      result = await recorder.permissions.requestRequiredPermissions()
    } else {
      await recorder.permissions.requestMicrophonePermission()
      result = recorder.permissions.microphone == .authorized ? .granted : .microphoneDenied
    }
    io.emit(["event": "permission.result", "value": result.rawValue])
    io.respond(id: command.id, result: [
      "microphone": recorder.permissions.microphone.rawValue,
      "screen": recorder.permissions.systemAudio.rawValue,
      "result": result.rawValue
    ])
  }

  // MARK: - Recording

  private func handleRecordStart(_ command: IncomingCommand) async throws {
    switch recorder.status {
    case .recording, .paused, .requestingPermissions, .finalizing:
      throw SidecarError.message(code: "alreadyRecording", text: "A recording is already in progress.")
    case .idle, .completed, .failed:
      break
    }

    if command.outputDir != nil {
      io.log("record.start: outputDir is ignored since Phase 3; the recordings root governs (use storage.setRecordingsRoot).")
    }

    let title = command.title ?? ""
    let localeId = command.localeId ?? Locale.defaultRecordingLocaleIdentifier
    await recorder.startRecording(
      title: title,
      localeIdentifier: localeId,
      microphoneDeviceID: command.micDeviceId
    )

    guard recorder.status == .recording, let document = recorder.currentDocument else {
      if let guidance = recorder.permissionGuidance {
        io.emit(["event": "permission.result", "value": guidance.rawValue])
      }
      let message = recorder.errorMessage ?? "Recording could not start."
      recorder.discardCurrentError()
      throw SidecarError.message(code: "startFailed", text: message)
    }

    let directory = store.recordingDirectory(for: document.metadata)
    var result: [String: Any] = [
      "recordingId": document.metadata.id.uuidString,
      "folderName": document.metadata.folderName,
      "outputDir": directory.path,
      "title": document.metadata.title,
      "localeId": document.metadata.localeIdentifier
    ]
    if let name = document.metadata.systemAudioFileName {
      result["systemAudioPath"] = directory.appendingPathComponent(name).path
    }
    if let name = document.metadata.microphoneAudioFileName {
      result["microphoneAudioPath"] = directory.appendingPathComponent(name).path
    }
    io.respond(id: command.id, result: result)
  }

  private func handleRecordPause(_ command: IncomingCommand) throws {
    guard recorder.status == .recording else {
      throw SidecarError.message(code: "notRecording", text: "No active recording to pause.")
    }
    recorder.pause()
    io.respond(id: command.id, result: ["status": recorder.status.rawValue])
  }

  private func handleRecordResume(_ command: IncomingCommand) throws {
    guard recorder.status == .paused else {
      throw SidecarError.message(code: "notPaused", text: "No paused recording to resume.")
    }
    recorder.resume()
    io.respond(id: command.id, result: ["status": recorder.status.rawValue])
  }

  private func handleRecordMuteMic(_ command: IncomingCommand) throws {
    guard recorder.status == .recording || recorder.status == .paused else {
      throw SidecarError.message(code: "notRecording", text: "No recording is in progress.")
    }
    let muted = command.muted ?? true
    recorder.setMicrophoneMuted(muted)
    io.respond(id: command.id, result: ["muted": muted])
  }

  private func handleRecordStop(_ command: IncomingCommand) async throws {
    guard recorder.status == .recording || recorder.status == .paused else {
      throw SidecarError.message(code: "notRecording", text: "No recording is in progress.")
    }

    await recorder.stop()

    guard let document = recorder.currentDocument else {
      throw SidecarError.message(code: "internal", text: "The recording produced no document.")
    }
    if recorder.status == .failed {
      throw SidecarError.message(code: "stopFailed", text: recorder.errorMessage ?? "The recording could not be finalised.")
    }

    let directory = store.recordingDirectory(for: document.metadata)
    var result: [String: Any] = [
      "recordingId": document.metadata.id.uuidString,
      "folderName": document.metadata.folderName,
      "outputDir": directory.path,
      "title": document.metadata.title,
      "status": document.metadata.status.rawValue,
      "durationSeconds": document.metadata.duration,
      "activeDurationSeconds": document.metadata.activeDuration,
      "transcriptSegments": document.transcript.count
    ]
    if let name = document.metadata.systemAudioFileName {
      let path = directory.appendingPathComponent(name).path
      result["systemAudioPath"] = path
      result["systemBytes"] = Self.fileSize(atPath: path)
    }
    if let name = document.metadata.microphoneAudioFileName {
      let path = directory.appendingPathComponent(name).path
      result["microphoneAudioPath"] = path
      result["microphoneBytes"] = Self.fileSize(atPath: path)
    }
    io.emit(["event": "library.changed"])
    io.respond(id: command.id, result: result)
  }

  // MARK: - Model

  private func handleModelStatus(_ command: IncomingCommand) {
    modelManager.refreshStatus()
    var result = modelStatusFields(modelManager.status)
    result["modelId"] = modelManager.modelName
    result["modelPath"] = modelManager.modelFolder.path
    result["isOnDisk"] = modelManager.isModelOnDisk()
    if let bytes = modelManager.onDiskSizeBytes {
      result["onDiskBytes"] = bytes
    }
    io.respond(id: command.id, result: result)
  }

  private func handleModelDownload(_ command: IncomingCommand) throws {
    if let modelId = command.modelId, modelId != modelManager.modelName {
      throw SidecarError.message(
        code: "badRequest",
        text: "Only \"\(modelManager.modelName)\" is available in this build."
      )
    }
    modelManager.startDownload()
    io.respond(id: command.id, result: [
      "started": true,
      "modelId": modelManager.modelName
    ])
  }

  private func handleModelSetLocation(_ command: IncomingCommand) async throws {
    guard let path = command.path, !path.isEmpty else {
      throw SidecarError.message(code: "badRequest", text: "\"path\" is required.")
    }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try await modelManager.updateDownloadBase(to: url, moveExisting: command.move ?? false)
    StorageLocationPreferences.setModelDirectory(url)
    io.respond(id: command.id, result: [
      "downloadBase": url.path,
      "modelPath": modelManager.modelFolder.path,
      "isOnDisk": modelManager.isModelOnDisk()
    ])
  }

  // MARK: - Library

  private func resolveMetadata(_ recordingId: String?) async throws -> RecordingMetadata {
    guard let recordingId, let uuid = UUID(uuidString: recordingId) else {
      throw SidecarError.message(code: "badRequest", text: "A valid \"recordingId\" is required.")
    }
    if let found = store.recordings.first(where: { $0.id == uuid }) {
      return found
    }
    await store.reload()
    if let found = store.recordings.first(where: { $0.id == uuid }) {
      return found
    }
    throw SidecarError.message(code: "notFound", text: "No recording with id \(recordingId).")
  }

  private func handleLibraryList(_ command: IncomingCommand) async throws {
    await store.reload()
    let recordings: [[String: Any]] = try store.recordings.map { metadata in
      var object = try JSONCoding.object(metadata)
      object["hasAudio"] = store.hasAudioFiles(for: metadata)
      return object
    }
    var result: [String: Any] = [
      "recordings": recordings,
      "rootDir": store.rootDirectory.path,
      "audioStorageBytes": store.audioStorageBytes
    ]
    if let warning = store.lastLoadError {
      result["warning"] = warning
    }
    io.respond(id: command.id, result: result)
  }

  private func handleLibraryDocument(_ command: IncomingCommand) async throws {
    let metadata = try await resolveMetadata(command.recordingId)
    let document = try store.document(for: metadata)
    io.respond(id: command.id, result: try JSONCoding.object(document))
  }

  private func handleLibraryRename(_ command: IncomingCommand) async throws {
    let metadata = try await resolveMetadata(command.recordingId)
    guard let title = command.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SidecarError.message(code: "badRequest", text: "A non-empty \"title\" is required.")
    }
    try store.rename(metadata, to: title)
    io.emit(["event": "library.changed"])
    io.respond(id: command.id, result: [
      "recordingId": metadata.id.uuidString,
      "title": title.trimmingCharacters(in: .whitespacesAndNewlines)
    ])
  }

  private func handleLibraryDelete(_ command: IncomingCommand) async throws {
    let metadata = try await resolveMetadata(command.recordingId)
    try store.delete(metadata)
    io.emit(["event": "library.changed"])
    io.respond(id: command.id, result: ["deleted": true])
  }

  private func handleLibraryRevealAudio(_ command: IncomingCommand) async throws {
    let metadata = try await resolveMetadata(command.recordingId)
    let hasAudio = store.hasAudioFiles(for: metadata)
    store.revealAudioFiles(metadata)
    io.respond(id: command.id, result: ["revealed": hasAudio])
  }

  // MARK: - Export

  private func handleExportMarkdown(_ command: IncomingCommand) async throws {
    let metadata = try await resolveMetadata(command.recordingId)
    let document = try store.document(for: metadata)
    io.respond(id: command.id, result: [
      "markdown": MarkdownExporter.markdown(for: document)
    ])
  }

  private func handleExportAIContext(_ command: IncomingCommand) async throws {
    let metadata = try await resolveMetadata(command.recordingId)
    let document = try store.document(for: metadata)
    let defaults = MarkdownExporter.AIContextOptions()
    let options = MarkdownExporter.AIContextOptions(
      includeDate: command.options?.date ?? defaults.includeDate,
      includeDuration: command.options?.duration ?? defaults.includeDuration,
      includeLocale: command.options?.locale ?? defaults.includeLocale,
      includeStatus: command.options?.status ?? defaults.includeStatus,
      includeFiles: command.options?.files ?? defaults.includeFiles,
      includePauses: command.options?.pauses ?? defaults.includePauses
    )
    io.respond(id: command.id, result: [
      "text": MarkdownExporter.aiContext(for: document, options: options)
    ])
  }

  // MARK: - Storage

  private func handleStorageSetRecordingsRoot(_ command: IncomingCommand) async throws {
    guard let path = command.path, !path.isEmpty else {
      throw SidecarError.message(code: "badRequest", text: "\"path\" is required.")
    }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try await store.updateRootDirectory(to: url, moveExisting: command.move ?? false)
    StorageLocationPreferences.setRecordingsDirectory(url)
    io.emit(["event": "library.changed"])
    io.respond(id: command.id, result: ["rootDir": store.rootDirectory.path])
  }

  private func handleStorageUsage(_ command: IncomingCommand) async {
    await store.reload()
    io.respond(id: command.id, result: [
      "rootDir": store.rootDirectory.path,
      "audioStorageBytes": store.audioStorageBytes,
      "recordings": store.recordings.count,
      "isReachable": store.isRootDirectoryReachable,
      "retentionPolicy": AudioStoragePreferences.policy().rawValue,
      "storageLimitBytes": AudioStoragePreferences.storageLimitBytes()
    ])
  }

  private func handleStorageSetRetention(_ command: IncomingCommand) throws {
    guard let raw = command.policy, let policy = AudioRetentionPolicy(rawValue: raw) else {
      let valid = AudioRetentionPolicy.allCases.map(\.rawValue).joined(separator: ", ")
      throw SidecarError.message(code: "badRequest", text: "\"policy\" must be one of: \(valid).")
    }
    let defaults = UserDefaults.standard
    defaults.set(policy.rawValue, forKey: AudioStoragePreferences.policyKey)
    if let limitBytes = command.limitBytes {
      defaults.set(limitBytes, forKey: AudioStoragePreferences.storageLimitKey)
    }
    io.respond(id: command.id, result: [
      "retentionPolicy": AudioStoragePreferences.policy().rawValue,
      "storageLimitBytes": AudioStoragePreferences.storageLimitBytes()
    ])
  }

  private func handleStorageApplyRetention(_ command: IncomingCommand) async throws {
    await store.reload()
    try store.applyConfiguredAudioCleanupIfNeeded()
    io.emit(["event": "library.changed"])
    io.respond(id: command.id, result: [
      "audioStorageBytes": store.audioStorageBytes,
      "retentionPolicy": AudioStoragePreferences.policy().rawValue
    ])
  }

  // MARK: - Helpers

  private static func fileSize(atPath path: String) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? Int) ?? 0
  }
}
