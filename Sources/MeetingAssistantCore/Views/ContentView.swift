import Foundation
import SwiftUI

public struct ContentView: View {
  @State private var session = AppSession.shared
  @State private var selectedRecordingID: UUID?
  @State private var searchText = ""
  @Environment(\.openSettings) private var openSettings

  @MainActor
  public init() {}

  public var body: some View {
    NavigationSplitView {
      SidebarView(
        recordings: filteredRecordings,
        selection: $selectedRecordingID
      )
      .searchable(text: $searchText, placement: .sidebar)
      .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
    } detail: {
      if recorderIsActive {
        RecorderPanelView(recorder: session.recorder)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let selectedRecording {
        RecordingDetailView(metadata: selectedRecording, store: session.store)
      } else {
        NewRecordingLandingView(selection: $selectedRecordingID)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          selectedRecordingID = nil
        } label: {
          Label("New Recording", systemImage: "plus.circle")
        }
        .help("New Recording (⌘N)")
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(selectedRecordingID == nil)
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          openSettings()
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .help("Open Settings (⌘,)")
        .keyboardShortcut(",", modifiers: [.command])
      }
    }
    .task {
      await session.store.reload()
    }
    .onReceive(NotificationCenter.default.publisher(for: .meetingAssistantRefreshRecordings)) { _ in
      Task {
        await session.store.reload()
      }
    }
  }

  private var selectedRecording: RecordingMetadata? {
    session.store.recordings.first { $0.id == selectedRecordingID }
  }

  /// True while a recording is being set up or captured, so the detail pane shows the live
  /// recorder screen. Because `startRecording` flips the status to `.requestingPermissions`
  /// synchronously (before its first await), this turns true the instant Start is tapped, so
  /// the recording page opens immediately. It flips back to false once the recorder reaches
  /// `.completed`/`.failed`, revealing the selected recording's transcript.
  private var recorderIsActive: Bool {
    switch session.recorder.status {
    case .requestingPermissions, .recording, .paused, .finalizing:
      return true
    default:
      return false
    }
  }

  private var filteredRecordings: [RecordingMetadata] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return session.store.recordings }
    return session.store.recordings.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || $0.localeIdentifier.localizedCaseInsensitiveContains(query)
        || $0.status.rawValue.localizedCaseInsensitiveContains(query)
    }
  }
}

private struct NewRecordingLandingView: View {
  @Binding var selection: UUID?

  @AppStorage("selectedMicrophoneDeviceID") private var selectedMicrophoneDeviceID = ""
  @State private var title = ""
  @State private var modelManager = ModelDownloadManager.shared
  @State private var recorder = AppSession.shared.recorder
  @Environment(\.openSettings) private var openSettings
  @FocusState private var titleFocused: Bool

  var body: some View {
    VStack(spacing: 28) {
      Spacer(minLength: 12)

      VStack(spacing: 10) {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.tint)
        Text("MeetingAssistant")
          .font(.largeTitle.weight(.semibold))
        Text("Capture a meeting and transcribe it locally on this Mac.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 12) {
        TextField("Meeting title", text: $title)
          .textFieldStyle(.roundedBorder)
          .font(.title3)
          .focused($titleFocused)
          .frame(maxWidth: 420)
          .onSubmit(start)

        Button(action: start) {
          Label("Start Recording", systemImage: "record.circle")
            .font(.headline)
            .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!canStart)
        .help(canStart ? "" : (modelOnDisk ? "" : "Download the Whisper model in Settings before recording."))
      }

      if !modelOnDisk {
        Button("Open Settings to download model") {
          openSettings()
        }
        .buttonStyle(.link)
      }

      if let errorMessage = recorder.errorMessage {
        Text(errorMessage)
          .font(.callout)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 420)
          .textSelection(.enabled)
      }

      Spacer()
    }
    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      modelManager.refreshStatus()
      titleFocused = true
    }
  }

  private var modelOnDisk: Bool {
    modelManager.isModelOnDisk()
  }

  private var canStart: Bool {
    guard modelOnDisk else { return false }
    switch recorder.status {
    case .idle, .completed, .failed:
      return true
    default:
      return false
    }
  }

  private func start() {
    guard canStart else { return }
    let microphoneDeviceID = selectedMicrophoneDeviceID.isEmpty ? nil : selectedMicrophoneDeviceID
    Task {
      await recorder.startRecording(
        title: title,
        localeIdentifier: Locale.defaultRecordingLocaleIdentifier,
        microphoneDeviceID: microphoneDeviceID
      )
      // Only switch to the live view if the recording actually began. A failed start
      // (e.g. denied permission) leaves us on the landing view with the error shown.
      if recorder.status == .recording, let id = recorder.currentDocument?.metadata.id {
        selection = id
        title = ""
      }
    }
  }
}
