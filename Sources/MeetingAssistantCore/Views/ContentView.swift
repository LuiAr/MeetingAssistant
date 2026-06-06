import AppKit
import Foundation
import SwiftUI

public struct ContentView: View {
  @State private var session = AppSession.shared
  @State private var selectedRecordingID: UUID?
  @State private var searchText = ""
  @State private var showInfo = false
  @State private var copyConfirmation: String?
  @State private var copyConfirmationToken = 0
  @Environment(\.openSettings) private var openSettings

  @MainActor
  public init() {}

  public var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      SidebarView(
        recordings: filteredRecordings,
        selection: $selectedRecordingID,
        searchText: $searchText,
        store: session.store
      )
      .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      if recorderIsActive {
        RecorderPanelView(recorder: session.recorder)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .navigationTitle("Recording")
      } else if let selectedRecording {
        RecordingDetailView(metadata: selectedRecording, store: session.store)
      } else {
        NewRecordingLandingView(selection: $selectedRecordingID)
          .navigationTitle("MeetingAssistant")
      }
    }
    // Each detail state sets its own navigation title so the window title reflects the
    // current view (the meeting title, "Recording", or the app name on the landing view).
    .inspector(isPresented: inspectorPresented) {
      if let selectedRecording, !recorderIsActive {
        RecordingInfoPanel(metadata: selectedRecording, store: session.store)
          .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
      }
    }
    .toolbar {
      // 1. Copy AI Context — its own group, only while a recording is shown.
      if showDetailActions {
        ToolbarItem(placement: .primaryAction) {
          Button {
            copyAIContext()
          } label: {
            Label("Copy AI Context", systemImage: "sparkles")
          }
          .labelStyle(.titleAndIcon)
          .help("Copy this meeting as AI-ready context — title, transcript, and any details enabled in Info")
        }
        ToolbarSpacer(.fixed)
      }

      // 2. New meeting + Settings — always available, grouped together.
      ToolbarItem(placement: .primaryAction) {
        Button {
          selectedRecordingID = nil
        } label: {
          Label("New meeting", systemImage: "plus.circle")
            .labelStyle(.titleAndIcon)
        }
        .help("Start a new meeting (⌘N)")
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

      // 3. More, then 4. Info — only while a recording is shown, each its own group.
      if showDetailActions {
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              revealSelectedInFinder()
            } label: {
              Label("Reveal folder", systemImage: "folder")
            }
            Button {
              copyTranscriptOnly()
            } label: {
              Label("Copy only transcript", systemImage: "doc.on.doc")
            }
          } label: {
            Label("More", systemImage: "ellipsis.circle")
          }
          .help("More actions — reveal folder, copy transcript")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
          Button {
            showInfo.toggle()
          } label: {
            Label("Info", systemImage: "info.circle")
          }
          .help("Show recording details")
        }
      }
    }
    .overlay(alignment: .center) {
      if let copyConfirmation {
        Label(copyConfirmation, systemImage: "checkmark.circle.fill")
          .font(.headline)
          .padding(.horizontal, 22)
          .padding(.vertical, 14)
          .background(.regularMaterial, in: Capsule())
          .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
          .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
          .transition(.opacity.combined(with: .scale(scale: 0.92)))
          .allowsHitTesting(false)
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

  /// Drives the info inspector. It auto-closes whenever there is no selected recording or a
  /// recording is in progress, while remembering the user's `showInfo` preference so it
  /// reopens once a recording's detail is shown again.
  private var inspectorPresented: Binding<Bool> {
    Binding(
      get: { showInfo && selectedRecording != nil && !recorderIsActive },
      set: { showInfo = $0 }
    )
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

  /// True while a selected recording's transcript is on screen (not the landing or live
  /// recorder views). Gates the detail-specific toolbar actions.
  private var showDetailActions: Bool {
    selectedRecording != nil && !recorderIsActive
  }

  private func copyAIContext() {
    guard let metadata = selectedRecording,
          let document = try? session.store.document(for: metadata) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      MarkdownExporter.aiContext(for: document, options: aiContextOptions),
      forType: .string
    )
    confirmCopy("AI context copied")
  }

  private func copyTranscriptOnly() {
    guard let metadata = selectedRecording else { return }
    let text: String
    if let document = try? session.store.document(for: metadata) {
      text = MarkdownExporter.transcript(for: document)
    } else {
      text = session.store.transcriptText(for: metadata)
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    confirmCopy("Transcript copied")
  }

  private func revealSelectedInFinder() {
    guard let metadata = selectedRecording else { return }
    session.store.revealInFinder(metadata)
  }

  /// Reads the "Include in AI Context" toggles from defaults. `UserDefaults.bool` returns
  /// false for unset keys, but date and duration default to true, so each flag falls back
  /// to its real default when the key has never been written.
  private var aiContextOptions: MarkdownExporter.AIContextOptions {
    let defaults = UserDefaults.standard
    func flag(_ key: String, default fallback: Bool) -> Bool {
      defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
    return MarkdownExporter.AIContextOptions(
      includeDate: flag(AIContextKey.date, default: true),
      includeDuration: flag(AIContextKey.duration, default: true),
      includeLocale: flag(AIContextKey.locale, default: false),
      includeStatus: flag(AIContextKey.status, default: false),
      includeFiles: flag(AIContextKey.files, default: false),
      includePauses: flag(AIContextKey.pauses, default: false)
    )
  }

  private func confirmCopy(_ message: String) {
    copyConfirmationToken += 1
    let token = copyConfirmationToken
    withAnimation(.spring(duration: 0.25)) { copyConfirmation = message }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.8))
      if token == copyConfirmationToken {
        withAnimation(.easeOut(duration: 0.3)) { copyConfirmation = nil }
      }
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
