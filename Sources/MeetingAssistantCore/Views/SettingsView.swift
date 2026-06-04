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
    }
    .frame(width: 620, height: 460)
    .scenePadding()
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
        Button {
          manager.startDownload()
        } label: {
          Label("Load Model", systemImage: "play.circle")
        }
        .buttonStyle(.borderedProminent)
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
    case .downloaded: return .yellow
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
