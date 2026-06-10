import Foundation
import MeetingAssistantCore
import XCTest

// Seam regression checks for the frozen sidecar contract (see ../../CONTRACT.md). Each test
// spawns the real sidecar binary and speaks NDJSON at it over stdio, exactly as the Tauri
// shell does. Tests that need a recordings library redirect the sidecar's recordings root to
// a temp folder and restore the default afterwards, so they never touch the real library.
// The capture test records real audio and transcribes it, so it is skipped with a message
// when the test runner's host (your terminal app) lacks Microphone or Screen Recording
// permission, or when the Whisper model is not on disk.

private let sidecarBinaryName = "meetingcore-sidecar"
private let expectedBundleId = "com.devswift.MeetingAssistant.rebuild.sidecar"
private let expectedProtocolVersion = 1
private let permissionStates: Set<String> = ["unknown", "authorized", "denied", "restricted"]
private let modelStatusValues: Set<String> = [
  "unknown", "notDownloaded", "downloading", "waitingForNetwork", "downloaded", "loading", "ready", "failed"
]

enum SeamError: Error, CustomStringConvertible {
  case binaryMissing
  case timedOut(String)

  var description: String {
    switch self {
    case .binaryMissing:
      return "Could not find the \(sidecarBinaryName) binary. Run \"swift build\" first, or set MEETINGCORE_SIDECAR to its path."
    case .timedOut(let what):
      return "Timed out waiting for \(what)."
    }
  }
}

/// Spawns the sidecar and provides line-oriented, JSON-decoded access to its stdout.
final class SidecarHarness: @unchecked Sendable {
  private let process = Process()
  private let stdinPipe = Pipe()
  private let stdoutPipe = Pipe()
  private let condition = NSCondition()
  private var lines: [String] = []
  private var buffer = Data()

  static func locateBinary() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["MEETINGCORE_SIDECAR"], !override.isEmpty {
      return URL(fileURLWithPath: override)
    }
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
      let candidate = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(sidecarBinaryName)
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    throw SeamError.binaryMissing
  }

  func launch() throws {
    process.executableURL = try Self.locateBinary()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice
    stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else { return }
      let data = handle.availableData
      self.condition.lock()
      if data.isEmpty {
        handle.readabilityHandler = nil
      } else {
        self.buffer.append(data)
        while let newline = self.buffer.firstIndex(of: 0x0A) {
          let lineData = self.buffer[self.buffer.startIndex..<newline]
          self.buffer.removeSubrange(self.buffer.startIndex...newline)
          if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
            self.lines.append(line)
          }
        }
      }
      self.condition.signal()
      self.condition.unlock()
    }
    try process.run()
  }

  func send(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    sendRaw(data)
  }

  func sendRaw(_ data: Data) {
    let handle = stdinPipe.fileHandleForWriting
    handle.write(data)
    handle.write(Data([0x0A]))
  }

  func nextLine(deadline: Date) -> String? {
    condition.lock()
    defer { condition.unlock() }
    while lines.isEmpty {
      if !condition.wait(until: deadline) {
        return nil
      }
    }
    return lines.removeFirst()
  }

  /// Returns the first decoded stdout object matching the predicate, discarding others
  /// (interleaved levels events, statuses, and so on).
  func waitFor(_ what: String, timeout: TimeInterval = 10, where predicate: ([String: Any]) -> Bool) throws -> [String: Any] {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      guard let line = nextLine(deadline: deadline) else { break }
      guard let data = line.data(using: .utf8),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        continue
      }
      if predicate(object) {
        return object
      }
    }
    throw SeamError.timedOut(what)
  }

  func response(for id: String, timeout: TimeInterval = 10) throws -> [String: Any] {
    try waitFor("response \(id)", timeout: timeout) { ($0["id"] as? String) == id }
  }

  func okResult(for id: String, timeout: TimeInterval = 10) throws -> [String: Any] {
    let response = try response(for: id, timeout: timeout)
    guard response["ok"] as? Bool == true else {
      let error = response["error"] as? [String: Any]
      XCTFail("Command \(id) failed: \(error?["code"] ?? "?") \(error?["message"] ?? "")")
      return [:]
    }
    return response["result"] as? [String: Any] ?? [:]
  }

  func event(_ name: String, timeout: TimeInterval = 10) throws -> [String: Any] {
    try waitFor("event \(name)", timeout: timeout) { ($0["event"] as? String) == name }
  }

  func closeStdin() {
    try? stdinPipe.fileHandleForWriting.close()
  }

  func waitForExit(timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    return !process.isRunning
  }

  var terminationStatus: Int32 {
    process.terminationStatus
  }

  func shutdown() {
    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    if process.isRunning {
      process.terminate()
    }
  }
}

final class SeamTests: XCTestCase {
  private var harness: SidecarHarness!
  private var commandCounter = 0

  override func setUpWithError() throws {
    harness = SidecarHarness()
    try harness.launch()
  }

  override func tearDown() {
    harness?.shutdown()
    harness = nil
  }

  private func newId() -> String {
    commandCounter += 1
    return "t\(commandCounter)"
  }

  private func sendCommand(_ cmd: String, _ params: [String: Any] = [:]) throws -> String {
    let id = newId()
    var object: [String: Any] = ["id": id, "cmd": cmd]
    for (key, value) in params {
      object[key] = value
    }
    try harness.send(object)
    return id
  }

  /// The default recordings root, as the sidecar resolves it. Setting the root back to this
  /// path clears the override in the sidecar's defaults domain.
  private static var defaultRecordingsRoot: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeetingAssistant Recordings", isDirectory: true)
  }

  private func redirectRecordingsRoot(to url: URL) throws {
    let id = try sendCommand("storage.setRecordingsRoot", ["path": url.path, "move": false])
    let result = try harness.okResult(for: id)
    XCTAssertEqual(result["rootDir"] as? String, url.path)
  }

  private func restoreDefaultRecordingsRoot() {
    guard let id = try? sendCommand("storage.setRecordingsRoot", ["path": Self.defaultRecordingsRoot.path, "move": false]) else { return }
    _ = try? harness.response(for: id)
  }

  // MARK: - Protocol basics

  func testReadyIsTheFirstLineAndCarriesIdentity() throws {
    let deadline = Date().addingTimeInterval(10)
    let first = try XCTUnwrap(harness.nextLine(deadline: deadline))
    let object = try XCTUnwrap(
      (try? JSONSerialization.jsonObject(with: Data(first.utf8))) as? [String: Any]
    )
    XCTAssertEqual(object["event"] as? String, "ready")
    XCTAssertEqual(object["protocol"] as? Int, expectedProtocolVersion)
    XCTAssertEqual(object["bundleId"] as? String, expectedBundleId)
    XCTAssertGreaterThan(object["pid"] as? Int ?? 0, 0)
    XCTAssertNotNil(object["sidecar"] as? String)
  }

  func testUnknownCommandIsRejectedAsUnsupported() throws {
    let id = try sendCommand("definitely.not.a.command")
    let response = try harness.response(for: id)
    XCTAssertEqual(response["ok"] as? Bool, false)
    let error = try XCTUnwrap(response["error"] as? [String: Any])
    XCTAssertEqual(error["code"] as? String, "unsupportedCommand")
  }

  func testMalformedLineEmitsProtocolError() throws {
    harness.sendRaw(Data("this is not json".utf8))
    let event = try harness.event("error")
    XCTAssertEqual(event["scope"] as? String, "protocol")
    XCTAssertEqual(event["code"] as? String, "badRequest")
  }

  func testExitsCleanlyOnStdinEOF() throws {
    _ = try harness.event("ready")
    harness.closeStdin()
    XCTAssertTrue(harness.waitForExit(timeout: 10), "sidecar did not exit after stdin EOF")
    XCTAssertEqual(harness.terminationStatus, 0)
  }

  // MARK: - Permissions and recording guards

  func testPermissionsStatusReturnsFrozenShape() throws {
    let id = try sendCommand("permissions.status")
    let result = try harness.okResult(for: id)
    let microphone = try XCTUnwrap(result["microphone"] as? String)
    let screen = try XCTUnwrap(result["screen"] as? String)
    XCTAssertTrue(permissionStates.contains(microphone))
    XCTAssertTrue(permissionStates.contains(screen))
  }

  func testRecordingGuardsWithoutActiveRecording() throws {
    for (cmd, expectedCode) in [
      ("record.stop", "notRecording"),
      ("record.pause", "notRecording"),
      ("record.resume", "notPaused"),
      ("record.muteMic", "notRecording")
    ] {
      let id = try sendCommand(cmd)
      let response = try harness.response(for: id)
      XCTAssertEqual(response["ok"] as? Bool, false, cmd)
      let error = try XCTUnwrap(response["error"] as? [String: Any], cmd)
      XCTAssertEqual(error["code"] as? String, expectedCode, cmd)
    }
  }

  // MARK: - Model

  func testModelStatusReturnsFrozenShape() throws {
    let id = try sendCommand("model.status")
    let result = try harness.okResult(for: id)
    XCTAssertEqual(result["modelId"] as? String, "openai_whisper-large-v3-v20240930_turbo")
    XCTAssertNotNil(result["modelPath"] as? String)
    XCTAssertNotNil(result["isOnDisk"] as? Bool)
    let value = try XCTUnwrap(result["value"] as? String)
    XCTAssertTrue(modelStatusValues.contains(value))
  }

  // MARK: - Library, export, storage (fixture-driven, no recording needed)

  func testLibraryExportStorageLifecycleWithFixture() throws {
    let fixtureURL = try XCTUnwrap(
      Bundle.module.url(forResource: "recording", withExtension: "json", subdirectory: "Fixtures")
    )
    let fixtureData = try Data(contentsOf: fixtureURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let fixture = try decoder.decode(RecordingDocument.self, from: fixtureData)
    let recordingId = fixture.metadata.id.uuidString

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("MeetingAssistant-seam-library-\(UUID().uuidString)", isDirectory: true)
    let folder = tempRoot.appendingPathComponent(fixture.metadata.folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try fixtureData.write(to: folder.appendingPathComponent("recording.json"))
    try "# Weekly planning\n".write(
      to: folder.appendingPathComponent(fixture.metadata.transcriptFileName),
      atomically: true,
      encoding: .utf8
    )
    defer {
      restoreDefaultRecordingsRoot()
      try? FileManager.default.removeItem(at: tempRoot)
    }

    try redirectRecordingsRoot(to: tempRoot)

    let listId = try sendCommand("library.list")
    let listResult = try harness.okResult(for: listId)
    let recordings = try XCTUnwrap(listResult["recordings"] as? [[String: Any]])
    XCTAssertEqual(recordings.count, 1)
    XCTAssertEqual(recordings[0]["id"] as? String, recordingId)
    XCTAssertEqual(recordings[0]["title"] as? String, "Weekly planning")
    XCTAssertEqual(recordings[0]["hasAudio"] as? Bool, false)

    let docId = try sendCommand("library.document", ["recordingId": recordingId])
    let docResult = try harness.okResult(for: docId)
    let docMetadata = try XCTUnwrap(docResult["metadata"] as? [String: Any])
    XCTAssertEqual(docMetadata["title"] as? String, "Weekly planning")
    XCTAssertEqual((docResult["transcript"] as? [[String: Any]])?.count, 2)

    let renameId = try sendCommand("library.rename", ["recordingId": recordingId, "title": "Planning (renamed)"])
    _ = try harness.okResult(for: renameId)

    let markdownId = try sendCommand("export.markdown", ["recordingId": recordingId])
    let markdownResult = try harness.okResult(for: markdownId)
    let markdown = try XCTUnwrap(markdownResult["markdown"] as? String)
    XCTAssertTrue(markdown.contains("Planning (renamed)"))

    let contextId = try sendCommand("export.aiContext", [
      "recordingId": recordingId,
      "options": ["date": false, "duration": true]
    ])
    let contextResult = try harness.okResult(for: contextId)
    let text = try XCTUnwrap(contextResult["text"] as? String)
    XCTAssertTrue(text.contains("Meeting: Planning (renamed)"))
    XCTAssertTrue(text.contains("Duration:"))
    XCTAssertFalse(text.contains("Date:"))

    let usageId = try sendCommand("storage.usage")
    let usageResult = try harness.okResult(for: usageId)
    XCTAssertEqual(usageResult["recordings"] as? Int, 1)
    XCTAssertEqual(usageResult["rootDir"] as? String, tempRoot.path)
    XCTAssertEqual(usageResult["isReachable"] as? Bool, true)

    let retentionId = try sendCommand("storage.setRetention", ["policy": "never"])
    let retentionResult = try harness.okResult(for: retentionId)
    XCTAssertEqual(retentionResult["retentionPolicy"] as? String, "never")

    let badRetentionId = try sendCommand("storage.setRetention", ["policy": "weekly"])
    let badRetention = try harness.response(for: badRetentionId)
    XCTAssertEqual(badRetention["ok"] as? Bool, false)

    let applyId = try sendCommand("storage.applyRetention")
    _ = try harness.okResult(for: applyId)

    let deleteId = try sendCommand("library.delete", ["recordingId": recordingId])
    let deleteResult = try harness.okResult(for: deleteId)
    XCTAssertEqual(deleteResult["deleted"] as? Bool, true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))

    let missingId = try sendCommand("library.document", ["recordingId": recordingId])
    let missing = try harness.response(for: missingId)
    XCTAssertEqual(missing["ok"] as? Bool, false)
    let missingError = try XCTUnwrap(missing["error"] as? [String: Any])
    XCTAssertEqual(missingError["code"] as? String, "notFound")
  }

  // MARK: - Capture end to end (needs permissions and the Whisper model)

  func testCaptureRoundTripRecordsAndTranscribes() throws {
    let permissionsId = try sendCommand("permissions.status")
    let permissions = try harness.okResult(for: permissionsId)
    guard permissions["microphone"] as? String == "authorized",
          permissions["screen"] as? String == "authorized" else {
      throw XCTSkip(
        "Capture check skipped: grant Microphone and Screen Recording to the app running these tests (your terminal) in System Settings, then re-run."
      )
    }

    let modelId = try sendCommand("model.status")
    let model = try harness.okResult(for: modelId)
    guard model["isOnDisk"] as? Bool == true else {
      throw XCTSkip(
        "Capture check skipped: the Whisper model is not on disk. Download it (native app or model.download) first."
      )
    }

    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("MeetingAssistant-seam-capture-\(UUID().uuidString)", isDirectory: true)
    defer {
      restoreDefaultRecordingsRoot()
      try? FileManager.default.removeItem(at: tempRoot)
    }
    try redirectRecordingsRoot(to: tempRoot)

    let startId = try sendCommand("record.start", ["title": "Seam capture check"])
    let startResult = try harness.okResult(for: startId, timeout: 30)
    let recordingId = try XCTUnwrap(startResult["recordingId"] as? String)
    let outputDir = try XCTUnwrap(startResult["outputDir"] as? String)
    XCTAssertTrue(outputDir.hasPrefix(tempRoot.path))
    let systemPath = try XCTUnwrap(startResult["systemAudioPath"] as? String)
    let microphonePath = try XCTUnwrap(startResult["microphoneAudioPath"] as? String)

    _ = try harness.waitFor("a levels event", timeout: 10) {
      ($0["event"] as? String) == "levels"
    }

    let muteId = try sendCommand("record.muteMic", ["muted": true])
    _ = try harness.okResult(for: muteId)
    let unmuteId = try sendCommand("record.muteMic", ["muted": false])
    _ = try harness.okResult(for: unmuteId)

    let pauseId = try sendCommand("record.pause")
    let pauseResult = try harness.okResult(for: pauseId)
    XCTAssertEqual(pauseResult["status"] as? String, "paused")
    let resumeId = try sendCommand("record.resume")
    let resumeResult = try harness.okResult(for: resumeId)
    XCTAssertEqual(resumeResult["status"] as? String, "recording")

    Thread.sleep(forTimeInterval: 2.0)

    // Stop triggers transcription: model load plus transcribing two short files. Generous
    // timeout because the first load of the large model can take a while.
    let stopId = try sendCommand("record.stop")
    let stopResult = try harness.okResult(for: stopId, timeout: 900)
    XCTAssertEqual(stopResult["recordingId"] as? String, recordingId)
    XCTAssertEqual(stopResult["status"] as? String, "completed")
    XCTAssertGreaterThan(stopResult["systemBytes"] as? Int ?? 0, 0)
    XCTAssertGreaterThan(stopResult["microphoneBytes"] as? Int ?? 0, 0)
    XCTAssertGreaterThan(stopResult["transcriptSegments"] as? Int ?? 0, 0)
    XCTAssertEqual((stopResult["durationSeconds"] as? Double ?? 0) > 0, true)

    let systemSize = try FileManager.default.attributesOfItem(atPath: systemPath)[.size] as? Int ?? 0
    let microphoneSize = try FileManager.default.attributesOfItem(atPath: microphonePath)[.size] as? Int ?? 0
    XCTAssertGreaterThan(systemSize, 0)
    XCTAssertGreaterThan(microphoneSize, 0)

    let jsonPath = (outputDir as NSString).appendingPathComponent("recording.json")
    let transcriptPath = (outputDir as NSString).appendingPathComponent("transcript.md")
    XCTAssertTrue(FileManager.default.fileExists(atPath: jsonPath))
    XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptPath))

    let pausesData = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let document = try decoder.decode(RecordingDocument.self, from: pausesData)
    XCTAssertEqual(document.metadata.status, .completed)
    XCTAssertEqual(document.pauses.count, 1)

    let listId = try sendCommand("library.list")
    let listResult = try harness.okResult(for: listId)
    let recordings = try XCTUnwrap(listResult["recordings"] as? [[String: Any]])
    XCTAssertTrue(recordings.contains { ($0["id"] as? String) == recordingId })

    let deleteId = try sendCommand("library.delete", ["recordingId": recordingId])
    _ = try harness.okResult(for: deleteId)
    XCTAssertFalse(FileManager.default.fileExists(atPath: outputDir))
  }
}

// Freezes the on-disk recording.json format by decoding a golden fixture with the core's
// own Codable types, re-encoding with the store's exact encoder settings, and asserting
// nothing changed shape. Catches renamed fields, changed date strategies, and the like.
final class OnDiskFormatTests: XCTestCase {
  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  func testRecordingDocumentFixtureRoundTrips() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: "recording", withExtension: "json", subdirectory: "Fixtures"),
      "Fixtures/recording.json is missing from the test bundle"
    )
    let data = try Data(contentsOf: url)
    let document = try Self.decoder().decode(RecordingDocument.self, from: data)

    XCTAssertEqual(document.metadata.title, "Weekly planning")
    XCTAssertEqual(document.metadata.status, .completed)
    XCTAssertEqual(document.metadata.localeIdentifier, "en_GB")
    XCTAssertEqual(document.metadata.transcriptFileName, "transcript.md")
    XCTAssertEqual(document.metadata.systemAudioFileName, "system.caf")
    XCTAssertEqual(document.metadata.microphoneAudioFileName, "microphone.caf")
    XCTAssertEqual(document.metadata.mixedAudioFileName, "mixed.caf")
    XCTAssertEqual(document.pauses.count, 1)
    XCTAssertEqual(document.transcript.count, 2)
    XCTAssertEqual(document.transcript[0].speaker, .you)
    XCTAssertEqual(document.transcript[1].speaker, .computerAudio)

    let reencoded = try Self.encoder().encode(document)
    let roundTripped = try Self.decoder().decode(RecordingDocument.self, from: reencoded)
    XCTAssertEqual(roundTripped, document)

    XCTAssertEqual(try Self.metadataKeys(in: reencoded), try Self.metadataKeys(in: data))
    XCTAssertEqual(try Self.topLevelKeys(in: reencoded), try Self.topLevelKeys(in: data))
  }

  private static func topLevelKeys(in data: Data) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return Set(object?.keys.map { String($0) } ?? [])
  }

  private static func metadataKeys(in data: Data) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let metadata = object?["metadata"] as? [String: Any]
    return Set(metadata?.keys.map { String($0) } ?? [])
  }
}
