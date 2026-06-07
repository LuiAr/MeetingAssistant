import AppKit
import SwiftUI

public struct SettingsView: View {
  public init() {}

  public var body: some View {
    TabView {
      ModelsSettingsView()
        .tabItem {
          Label("Models", systemImage: "sparkles")
        }
      AudioSettingsView()
        .tabItem {
          Label("Audio", systemImage: "mic")
        }
      StorageSettingsView()
        .tabItem {
          Label("Storage", systemImage: "internaldrive")
        }
    }
    .frame(width: 620, height: 460)
    .scenePadding()
  }
}

private struct StorageSettingsView: View {
  @State private var store = AppSession.shared.store
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
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recording Storage")
            .font(.title2.weight(.semibold))
          Text("Manage saved meeting audio without deleting transcripts or meeting details.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

            HStack(spacing: 10) {
              Button {
                applyCleanup()
              } label: {
                Label("Apply Cleanup Now", systemImage: "trash")
              }
              .disabled(policy == .never)

              Button {
                NSWorkspace.shared.open(store.rootDirectory)
              } label: {
                Label("Open Recordings Folder", systemImage: "folder")
              }
            }
          }
          .padding(8)
        }

        if let cleanupError {
          Text(cleanupError)
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      await store.reload()
    }
    .onChange(of: policyRaw) { _, _ in
      applyCleanup()
    }
    .onChange(of: storageLimitBytes) { _, _ in
      guard policy == .storageLimit else { return }
      applyCleanup()
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
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Microphone")
            .font(.title2.weight(.semibold))
          Text("Choose which input device is captured alongside the computer audio while recording.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

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
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task {
      microphones = MicrophoneDeviceProvider.devices()
    }
  }
}

private struct ModelsSettingsView: View {
  @State private var manager = ModelDownloadManager.shared
  @State private var showDeleteConfirm = false

  fileprivate static let sizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useMB, .useGB]
    f.countStyle = .file
    return f
  }()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Transcription Model")
            .font(.title2.weight(.semibold))
          Text("MeetingAssistant transcribes recordings on-device with WhisperKit. The model must be downloaded once before you can record.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

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
              LabeledContent("Size on Disk") {
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

        if let error = manager.lastError, isFailedState {
          Text(error)
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }

        catalogSection
      }
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear {
      manager.refreshStatus()
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
          Label("Download Model", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.borderedProminent)
      case .downloading, .waitingForNetwork:
        Button {
          manager.cancelDownload()
        } label: {
          Label("Cancel", systemImage: "xmark.circle")
        }
      case .downloaded:
        Button("Delete", role: .destructive) {
          showDeleteConfirm = true
        }
      case .loading:
        Button("Cancel", role: .cancel) {
          manager.cancelDownload()
        }
      case .ready:
        Button {
          NSWorkspace.shared.activateFileViewerSelecting([manager.modelFolder])
        } label: {
          Label("Reveal in Finder", systemImage: "folder")
        }
        Button("Delete", role: .destructive) {
          showDeleteConfirm = true
        }
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
    let recommendedID = WhisperModelCatalog.recommended().id

    VStack(alignment: .leading, spacing: 8) {
      Text("Available Models")
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
