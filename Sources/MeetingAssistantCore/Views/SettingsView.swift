import AppKit
import SwiftUI

public struct SettingsView: View {
  public init() {}

  public var body: some View {
    TabView {
      ModelsSettingsView()
        .tabItem {
          Label("Models", systemImage: "waveform.badge.gearshape")
        }
    }
    .frame(width: 620, height: 460)
    .scenePadding()
  }
}

private struct ModelsSettingsView: View {
  @State private var manager = ModelDownloadManager.shared
  @State private var showDeleteConfirm = false

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

            LabeledContent("Repository") {
              Text(manager.repo)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            }

            LabeledContent("Install Location") {
              Text(manager.modelFolder.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
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
