import Foundation
import SwiftUI

public struct ContentView: View {
  @State private var store: RecordingStore
  @State private var recorder: MeetingRecorder
  @State private var selectedRecordingID: UUID?
  @State private var searchText = ""
  @Environment(\.openSettings) private var openSettings

  @MainActor
  public init(rootDirectory: URL = RecordingStore.defaultRootDirectory) {
    let store = RecordingStore(rootDirectory: rootDirectory)
    _store = State(initialValue: store)
    _recorder = State(initialValue: MeetingRecorder(store: store))
  }

  public var body: some View {
    NavigationSplitView {
      SidebarView(
        recordings: filteredRecordings,
        selection: $selectedRecordingID
      )
      .searchable(text: $searchText, placement: .sidebar)
      .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
    } detail: {
      VStack(spacing: 0) {
        RecorderPanelView(recorder: recorder)
          .padding()

        Divider()

        if let selectedRecording {
          RecordingDetailView(metadata: selectedRecording, store: store)
        } else {
          EmptyLibraryView()
        }
      }
    }
    .toolbar {
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
      await store.reload()
      if selectedRecordingID == nil {
        selectedRecordingID = store.recordings.first?.id
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .meetingAssistantRefreshRecordings)) { _ in
      Task {
        await store.reload()
      }
    }
  }

  private var selectedRecording: RecordingMetadata? {
    store.recordings.first { $0.id == selectedRecordingID }
  }

  private var filteredRecordings: [RecordingMetadata] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return store.recordings }
    return store.recordings.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || $0.localeIdentifier.localizedCaseInsensitiveContains(query)
        || $0.status.rawValue.localizedCaseInsensitiveContains(query)
    }
  }
}

private struct EmptyLibraryView: View {
  var body: some View {
    ContentUnavailableView(
      "No Recording Selected",
      systemImage: "waveform.badge.magnifyingglass",
      description: Text("Start a recording or choose a saved meeting from the sidebar.")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
