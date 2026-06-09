#if DEBUG
import AppKit
import Foundation
import MeetingAssistantCore
import SwiftUI

struct SmokeRecordView: View {
  var seconds: Int

  @State private var store = RecordingStore(rootDirectory: StorageLocationPreferences.recordingsDirectory())
  @State private var recorder: MeetingRecorder?
  @State private var message = "Preparing smoke recording..."

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("MeetingAssistant Smoke Test")
        .font(.headline)
      Text(message)
        .foregroundStyle(.secondary)
      ProgressView()
        .controlSize(.small)
    }
    .padding()
    .task {
      await run()
    }
  }

  @MainActor
  private func run() async {
    let recorder = MeetingRecorder(store: store)
    self.recorder = recorder

    await store.reload()
    message = "Starting recording for \(seconds) seconds..."

    await recorder.startRecording(
      title: "Smoke Test \(Date().formatted(date: .omitted, time: .standard))",
      localeIdentifier: Locale.current.identifier,
      microphoneDeviceID: nil
    )

    guard recorder.status == .recording else {
      writeResult(
        SmokeRecordResult(
          status: recorder.status.rawValue,
          errorMessage: recorder.errorMessage ?? "Recording did not start.",
          recordingFolder: nil,
          transcriptPath: nil,
          systemAudioPath: nil,
          microphoneAudioPath: nil
        )
      )
      NSApp.terminate(nil)
      return
    }

    message = "Recording..."
    try? await Task.sleep(for: .seconds(seconds))
    message = "Stopping and finalizing..."
    await recorder.stop()

    let document = recorder.currentDocument
    let folder = document.map { store.recordingDirectory(for: $0.metadata).path }
    let transcript = document.map { store.transcriptURL(for: $0.metadata).path }
    let systemAudio = document.flatMap { document in
      document.metadata.systemAudioFileName.map {
        store.recordingDirectory(for: document.metadata).appendingPathComponent($0).path
      }
    }
    let microphoneAudio = document.flatMap { document in
      document.metadata.microphoneAudioFileName.map {
        store.recordingDirectory(for: document.metadata).appendingPathComponent($0).path
      }
    }

    writeResult(
      SmokeRecordResult(
        status: recorder.status.rawValue,
        errorMessage: recorder.errorMessage,
        recordingFolder: folder,
        transcriptPath: transcript,
        systemAudioPath: systemAudio,
        microphoneAudioPath: microphoneAudio
      )
    )
    NSApp.terminate(nil)
  }

  private func writeResult(_ result: SmokeRecordResult) {
    let url = SmokeRecordResult.resultURL
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      try data.write(to: url, options: [.atomic])
    } catch {
      try? "{\"status\":\"failed\",\"errorMessage\":\"Could not write smoke result.\"}"
        .write(to: url, atomically: true, encoding: .utf8)
    }
  }
}

private struct SmokeRecordResult: Codable {
  static let resultURL = URL(fileURLWithPath: "/tmp/MeetingAssistant-smoke-record-result.json")

  var status: String
  var errorMessage: String?
  var recordingFolder: String?
  var transcriptPath: String?
  var systemAudioPath: String?
  var microphoneAudioPath: String?
}
#endif

