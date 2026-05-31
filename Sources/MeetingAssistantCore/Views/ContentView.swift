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
      if let selectedRecording {
        RecordingDetailView(metadata: selectedRecording, store: session.store)
      } else {
        NewRecordingLandingView()
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
  @AppStorage("recordingLocaleIdentifier") private var localeIdentifier = Locale.defaultRecordingLocaleIdentifier
  @AppStorage("selectedMicrophoneDeviceID") private var selectedMicrophoneDeviceID = ""
  @State private var title = ""
  @State private var modelManager = ModelDownloadManager.shared
  @State private var recorder = AppSession.shared.recorder
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
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
    let session = NewRecordingSession(
      title: title,
      localeIdentifier: localeIdentifier,
      microphoneDeviceID: selectedMicrophoneDeviceID.isEmpty ? nil : selectedMicrophoneDeviceID
    )
    openWindow(id: "recording", value: session)
    // Clear the field so the next landing visit starts blank.
    title = ""
  }
}
