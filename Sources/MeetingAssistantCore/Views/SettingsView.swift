import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case recordings
  case transcription
  case audio

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .recordings: return "Recordings"
    case .transcription: return "Transcription"
    case .audio: return "Audio"
    }
  }

  var systemImage: String {
    switch self {
    case .general: return "gearshape"
    case .recordings: return "folder"
    case .transcription: return "sparkles"
    case .audio: return "mic"
    }
  }
}

public struct SettingsView: View {
  @State private var selection: SettingsSection? = .general

  public init() {}

  public var body: some View {
    NavigationSplitView {
      List(SettingsSection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      ScrollView {
        detail
          .padding(24)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(width: 800, height: 580)
  }

  @ViewBuilder
  private var detail: some View {
    switch selection ?? .general {
    case .general:
      GeneralSettingsView()
    case .recordings:
      RecordingsSettingsView()
    case .transcription:
      TranscriptionSettingsView()
    case .audio:
      AudioSettingsView()
    }
  }
}

private struct SettingsHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.title2.weight(.semibold))
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct GeneralSettingsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsHeader(
        title: "General",
        subtitle: "MeetingAssistant records and transcribes meetings entirely on this Mac."
      )

      GroupBox {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lock.shield")
            .font(.title3)
            .foregroundStyle(.tint)
          VStack(alignment: .leading, spacing: 6) {
            Text("On-device and private")
              .font(.callout.weight(.semibold))
            Text("Recording and transcription happen on-device. The only time the app uses the network is a one-time download of the transcription model.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .padding(8)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Text("Setup")
            .font(.callout.weight(.semibold))
          Text("Run the first-time setup again to review the storage locations, model download, and permissions.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button {
            OnboardingPreferences.reset()
            NSApp.activate(ignoringOtherApps: true)
          } label: {
            Label("Re-run setup", systemImage: "arrow.clockwise")
          }
          .pointingHandCursor()
          Text("This shows the setup wizard again in the main window. Your recordings and downloaded model are kept.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
      }
    }
  }
}

private struct RecordingsSettingsView: View {
  @State private var store = AppSession.shared.store
  @State private var pendingURL: URL?
  @State private var showMovePrompt = false
  @State private var locationError: String?
  @State private var cleanupError: String?

  @AppStorage(AudioStoragePreferences.policyKey) private var policyRaw = AudioRetentionPolicy.never.rawValue
  @AppStorage(AudioStoragePreferences.storageLimitKey) private var storageLimitBytes =
    AudioStoragePreferences.defaultStorageLimitBytes

  private static let sizeFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter
  }()

  private let storageLimits = [
    1_000_000_000,
    5_000_000_000,
    10_000_000_000,
    25_000_000_000,
    50_000_000_000
  ]

  private var policy: AudioRetentionPolicy {
    AudioRetentionPolicy(rawValue: policyRaw) ?? .never
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsHeader(
        title: "Recordings",
        subtitle: "Choose where meetings are saved and how long their audio is kept."
      )

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("Location") {
            Text(store.rootDirectory.path)
              .lineLimit(2)
              .truncationMode(.middle)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }

          if !store.isRootDirectoryReachable {
            Label("This folder is not currently available. It may be on a drive that is not connected.", systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }

          HStack(spacing: 10) {
            Button {
              chooseLocation()
            } label: {
              Label("Choose folder…", systemImage: "folder.badge.gearshape")
            }
            .pointingHandCursor()

            Button("Use default") {
              requestApply(StorageLocationPreferences.defaultRecordingsDirectory)
            }
            .disabled(!StorageLocationPreferences.isUsingCustomRecordingsDirectory())
            .pointingHandCursor(enabled: StorageLocationPreferences.isUsingCustomRecordingsDirectory())

            Button {
              NSWorkspace.shared.open(store.rootDirectory)
            } label: {
              Label("Reveal in Finder", systemImage: "folder")
            }
            .pointingHandCursor()

            Spacer()
          }

          if let locationError {
            Text(locationError)
              .font(.callout)
              .foregroundStyle(.red)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(8)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          LabeledContent("Audio storage used") {
            Text(Self.sizeFormatter.string(fromByteCount: store.audioStorageBytes))
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }

          Picker("Delete audio", selection: $policyRaw) {
            ForEach(AudioRetentionPolicy.allCases) { policy in
              Text(policy.displayName).tag(policy.rawValue)
            }
          }

          if policy == .storageLimit {
            Picker("Storage limit", selection: $storageLimitBytes) {
              ForEach(storageLimits, id: \.self) { bytes in
                Text(Self.sizeFormatter.string(fromByteCount: Int64(bytes))).tag(bytes)
              }
            }
          }

          Text("Cleanup removes only audio files. Transcripts and meeting details remain available.")
            .font(.caption)
            .foregroundStyle(.secondary)

          Button {
            applyCleanup()
          } label: {
            Label("Apply cleanup now", systemImage: "trash")
          }
          .disabled(policy == .never)
          .pointingHandCursor(enabled: policy != .never)

          if let cleanupError {
            Text(cleanupError)
              .font(.callout)
              .foregroundStyle(.red)
              .textSelection(.enabled)
          }
        }
        .padding(8)
      }
    }
    .task {
      await store.reload()
    }
    .confirmationDialog(
      "Move existing recordings to the new location?",
      isPresented: $showMovePrompt,
      titleVisibility: .visible
    ) {
      Button("Move existing recordings") { applyLocation(move: true) }
      Button("Use new location only") { applyLocation(move: false) }
      Button("Cancel", role: .cancel) { pendingURL = nil }
    } message: {
      Text("Choose whether to move the recordings already saved here, or leave them in place and only save new meetings to the new location.")
    }
    .onChange(of: policyRaw) { _, _ in
      applyCleanup()
    }
    .onChange(of: storageLimitBytes) { _, _ in
      guard policy == .storageLimit else { return }
      applyCleanup()
    }
  }

  private func chooseLocation() {
    guard let url = DirectoryPicker.chooseDirectory(
      message: "Choose a folder to store your meeting recordings."
    ) else { return }
    requestApply(url)
  }

  private func requestApply(_ url: URL) {
    guard url.standardizedFileURL != store.rootDirectory.standardizedFileURL else { return }
    pendingURL = url
    let hasExisting = !store.recordings.isEmpty
    if hasExisting {
      showMovePrompt = true
    } else {
      applyLocation(move: false)
    }
  }

  private func applyLocation(move: Bool) {
    guard let url = pendingURL else { return }
    pendingURL = nil
    StorageLocationPreferences.setRecordingsDirectory(url)
    Task {
      do {
        try await store.updateRootDirectory(to: StorageLocationPreferences.recordingsDirectory(), moveExisting: move)
        locationError = nil
      } catch {
        locationError = error.localizedDescription
      }
    }
  }

  private func applyCleanup() {
    do {
      try store.applyConfiguredAudioCleanupIfNeeded()
      cleanupError = nil
    } catch {
      cleanupError = error.localizedDescription
    }
  }
}

private struct AudioSettingsView: View {
  @AppStorage("selectedMicrophoneDeviceID") private var selectedMicrophoneDeviceID = ""
  @State private var microphones: [MicrophoneDevice] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsHeader(
        title: "Audio",
        subtitle: "Choose which input device is captured alongside the computer audio while recording."
      )

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          Picker("Input device", selection: $selectedMicrophoneDeviceID) {
            Text("System Default").tag("")
            ForEach(microphones) { microphone in
              Text(microphone.name).tag(microphone.id)
            }
          }
        }
        .padding(8)
      }
    }
    .task {
      microphones = MicrophoneDeviceProvider.devices()
    }
  }
}

private struct TranscriptionSettingsView: View {
  @State private var manager = ModelDownloadManager.shared
  @State private var showDeleteConfirm = false
  @State private var pendingURL: URL?
  @State private var showMovePrompt = false
  @State private var locationError: String?

  fileprivate static let sizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useMB, .useGB]
    f.countStyle = .file
    return f
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsHeader(
        title: "Transcription",
        subtitle: "MeetingAssistant transcribes recordings on-device with WhisperKit. The model must be downloaded once before you can record."
      )

      modelLocationBox
      modelStatusBox

      if let error = manager.lastError, isFailedState {
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      catalogSection
    }
    .onAppear {
      manager.refreshStatus()
    }
    .confirmationDialog(
      "Move the downloaded model?",
      isPresented: $showMovePrompt,
      titleVisibility: .visible
    ) {
      Button("Move model to new location") { applyLocation(move: true) }
      Button("Re-download later") { applyLocation(move: false) }
      Button("Cancel", role: .cancel) { pendingURL = nil }
    } message: {
      Text("The model is about 1.6 GB. Move it to the new location, or point there and download it again later.")
    }
    .confirmationDialog(
      "Delete downloaded model?",
      isPresented: $showDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        try? manager.deleteModel()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This frees disk space but you'll need to download again before your next recording.")
    }
  }

  private var modelLocationBox: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Location") {
          Text(manager.downloadBase.path)
            .lineLimit(2)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        if !manager.isDownloadBaseReachable {
          Label("This folder is not currently available. It may be on a drive that is not connected.", systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 10) {
          Button {
            chooseLocation()
          } label: {
            Label("Choose folder…", systemImage: "folder.badge.gearshape")
          }
          .pointingHandCursor()

          Button("Use default") {
            requestApply(StorageLocationPreferences.defaultModelDirectory)
          }
          .disabled(!StorageLocationPreferences.isUsingCustomModelDirectory())
          .pointingHandCursor(enabled: StorageLocationPreferences.isUsingCustomModelDirectory())

          Spacer()
        }

        if let locationError {
          Text(locationError)
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(8)
    }
  }

  private var modelStatusBox: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 14) {
        LabeledContent("Model") {
          Text(manager.modelName)
            .monospaced()
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }

        if let bytes = manager.onDiskSizeBytes {
          LabeledContent("Size on disk") {
            Text(Self.sizeFormatter.string(fromByteCount: bytes))
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
        }

        Divider()

        statusRow
        progressRow
        actionButtons
      }
      .padding(8)
    }
  }

  @ViewBuilder
  private var statusRow: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(statusColor)
        .frame(width: 9, height: 9)
      Text(manager.status.displayLabel)
        .foregroundStyle(.primary)
      Spacer()
    }
    .font(.callout)
  }

  @ViewBuilder
  private var progressRow: some View {
    switch manager.status {
    case .downloading(let fraction, _):
      ProgressView(value: fraction)
        .progressViewStyle(.linear)
    case .waitingForNetwork:
      ProgressView()
        .progressViewStyle(.linear)
    case .loading:
      ProgressView()
        .progressViewStyle(.linear)
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    HStack(spacing: 10) {
      switch manager.status {
      case .unknown, .notDownloaded, .failed:
        Button {
          manager.startDownload()
        } label: {
          Label("Download model", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.borderedProminent)
        .pointingHandCursor()
      case .downloading, .waitingForNetwork:
        Button {
          manager.cancelDownload()
        } label: {
          Label("Cancel", systemImage: "xmark.circle")
        }
        .pointingHandCursor()
      case .downloaded:
        Button("Delete", role: .destructive) {
          showDeleteConfirm = true
        }
        .pointingHandCursor()
      case .loading:
        Button("Cancel", role: .cancel) {
          manager.cancelDownload()
        }
        .pointingHandCursor()
      case .ready:
        Button {
          NSWorkspace.shared.activateFileViewerSelecting([manager.modelFolder])
        } label: {
          Label("Reveal in Finder", systemImage: "folder")
        }
        .pointingHandCursor()
        Button("Delete", role: .destructive) {
          showDeleteConfirm = true
        }
        .pointingHandCursor()
      }
    }
  }

  private var isFailedState: Bool {
    if case .failed = manager.status { return true }
    return false
  }

  @ViewBuilder
  private var catalogSection: some View {
    let activeID = manager.modelName
    let hostBytes = WhisperModelCatalog.hostPhysicalMemoryBytes
    let recommended = WhisperModelCatalog.recommended(forHostBytes: hostBytes)
    let recommendedID: String? = hostBytes >= recommended.recommendedMinRAMBytes ? recommended.id : nil

    VStack(alignment: .leading, spacing: 8) {
      Text("Available models")
        .font(.headline)
      Text("More variants will land here. Switching between them isn't available yet.")
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        ForEach(WhisperModelCatalog.all) { variant in
          ModelCatalogRow(
            variant: variant,
            isActive: variant.id == activeID,
            isRecommended: variant.id == recommendedID
          )
        }
      }
    }
  }

  private var statusColor: Color {
    switch manager.status {
    case .ready: return .green
    case .downloading, .loading, .waitingForNetwork: return .orange
    case .failed: return .red
    case .downloaded: return .green
    case .notDownloaded, .unknown: return .secondary
    }
  }

  private func chooseLocation() {
    guard let url = DirectoryPicker.chooseDirectory(
      message: "Choose a folder to store the transcription model (about 1.6 GB)."
    ) else { return }
    requestApply(url)
  }

  private func requestApply(_ url: URL) {
    guard url.standardizedFileURL != manager.downloadBase.standardizedFileURL else { return }
    pendingURL = url
    if manager.isModelOnDisk() {
      showMovePrompt = true
    } else {
      applyLocation(move: false)
    }
  }

  private func applyLocation(move: Bool) {
    guard let url = pendingURL else { return }
    pendingURL = nil
    StorageLocationPreferences.setModelDirectory(url)
    Task {
      do {
        try await manager.updateDownloadBase(to: StorageLocationPreferences.modelDirectory(), moveExisting: move)
        locationError = nil
      } catch {
        locationError = error.localizedDescription
      }
    }
  }
}

private struct ModelCatalogRow: View {
  let variant: WhisperModelVariant
  let isActive: Bool
  let isRecommended: Bool

  private static let sizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useMB, .useGB]
    f.countStyle = .file
    return f
  }()

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(variant.friendlyName)
            .font(.body.weight(.semibold))
          if isActive {
            badge("Active", tint: .green)
          }
          if isRecommended {
            badge("Recommended", tint: .accentColor)
          }
          Spacer()
          Text(variant.qualityTier.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(variant.summary)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 16) {
          metric("Download", value: Self.sizeFormatter.string(fromByteCount: variant.approxDownloadBytes))
          metric("RAM", value: Self.sizeFormatter.string(fromByteCount: variant.approxRAMBytes))
        }
        .font(.caption)
      }
      .padding(6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func badge(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(tint.opacity(0.15), in: Capsule())
      .foregroundStyle(tint)
  }

  @ViewBuilder
  private func metric(_ label: String, value: String) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .foregroundStyle(.secondary)
      Text(value)
        .monospacedDigit()
    }
  }
}
