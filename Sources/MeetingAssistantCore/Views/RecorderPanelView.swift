import SwiftUI

struct RecorderPanelView: View {
  var recorder: MeetingRecorder

  @State private var modelManager = ModelDownloadManager.shared
  @Environment(\.openSettings) private var openSettings

  private var isRecordingOrPaused: Bool {
    recorder.status == .recording || recorder.status == .paused
  }

  var body: some View {
    VStack(spacing: 28) {
      Spacer(minLength: 24)

      statusIcon

      VStack(spacing: 10) {
        Text(displayTitle)
          .font(.title2.weight(.semibold))
          .lineLimit(2)
          .multilineTextAlignment(.center)

        Text(TimecodeFormatter.string(from: recorder.activeElapsed))
          .font(.system(size: 56, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(isRecordingOrPaused ? .primary : .secondary)

        if recorder.status == .finalizing {
          TranscribingIndicator()
            .padding(.top, 6)
        } else {
          HStack(spacing: 8) {
            Circle()
              .fill(statusColor)
              .frame(width: 8, height: 8)
            Text(statusLabel)
              .foregroundStyle(.secondary)
          }
          .font(.callout)
        }
      }

      if isRecordingOrPaused {
        HStack(spacing: 20) {
          LevelMeterView(title: "Computer", level: recorder.levels.system)
          LevelMeterView(title: "Mic", level: recorder.levels.microphone)
        }

        controlButtons
          .padding(.top, 4)
      }

      if !isModelReady {
        ModelNotReadyBanner(status: modelManager.status) {
          openSettings()
        }
        .frame(maxWidth: 420)
      }

      if let captureWarning = recorder.captureWarning {
        Label(captureWarning, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.orange)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 420)
          .textSelection(.enabled)
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

      Spacer(minLength: 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
    .task {
      modelManager.refreshStatus()
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch recorder.status {
    case .recording:
      Image(systemName: "record.circle.fill")
        .font(.system(size: 68))
        .foregroundStyle(.red)
        .symbolEffect(.pulse, options: .repeating)
    case .paused:
      Image(systemName: "pause.circle.fill")
        .font(.system(size: 68))
        .foregroundStyle(.orange)
    case .finalizing, .requestingPermissions:
      ProgressView()
        .controlSize(.large)
        .frame(height: 68)
    default:
      Image(systemName: "waveform")
        .font(.system(size: 68))
        .foregroundStyle(.secondary)
    }
  }

  private var statusLabel: String {
    switch recorder.status {
    case .requestingPermissions:
      return "Requesting permissions…"
    case .finalizing:
      return "Saving & transcribing…"
    default:
      return recorder.status.displayName
    }
  }

  private var displayTitle: String {
    // While permissions are still being requested the draft for this recording doesn't
    // exist yet, so `currentDocument` may still point at the previous recording. Show a
    // neutral title until the new draft is created.
    guard recorder.status != .requestingPermissions else { return "Recording" }
    let trimmed = (recorder.currentDocument?.metadata.title ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Recording" : trimmed
  }

  private var isModelReady: Bool {
    modelManager.isModelOnDisk()
  }

  @ViewBuilder
  private var controlButtons: some View {
    HStack(spacing: 14) {
      Button {
        recorder.setMicrophoneMuted(!recorder.isMicrophoneMuted)
      } label: {
        Label(
          recorder.isMicrophoneMuted ? "Unmute Mic" : "Mute Mic",
          systemImage: recorder.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill"
        )
        .frame(minWidth: 90)
      }
      .controlSize(.large)
      .tint(recorder.isMicrophoneMuted ? .red : nil)
      .help("Mute your microphone — it is recorded as silence while muted")
      .pointerStyle(.link)

      if recorder.status == .paused {
        Button {
          recorder.resume()
        } label: {
          Label("Resume", systemImage: "play.fill")
            .frame(minWidth: 90)
        }
        .controlSize(.large)
        .pointerStyle(.link)
      } else {
        Button {
          recorder.pause()
        } label: {
          Label("Pause", systemImage: "pause.fill")
            .frame(minWidth: 90)
        }
        .controlSize(.large)
        .pointerStyle(.link)
      }

      Button {
        Task {
          await recorder.stop()
        }
      } label: {
        Label("Stop & Save", systemImage: "stop.fill")
          .frame(minWidth: 110)
      }
      .controlSize(.large)
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .pointerStyle(.link)
    }
  }

  private var statusColor: Color {
    switch recorder.status {
    case .recording:
      return .red
    case .paused:
      return .orange
    case .finalizing, .requestingPermissions:
      return .yellow
    case .failed:
      return .red
    default:
      return .secondary
    }
  }
}

/// Shown while the recording is being saved and transcribed. The percentage WhisperKit
/// reports per window is unreliable, so instead of a progress bar this cycles through
/// reassuring messages with a soft pulsing glow.
private struct TranscribingIndicator: View {
  private static let messages = [
    "Hang tight — transcribing your meeting…",
    "Working through the audio…",
    "This can take a moment…",
    "Almost there…",
    "Polishing the transcript…"
  ]

  @State private var index = 0
  @State private var glow = false

  var body: some View {
    Text(Self.messages[index])
      .font(.headline)
      .foregroundStyle(.tint)
      .contentTransition(.opacity)
      .multilineTextAlignment(.center)
      .shadow(color: .accentColor.opacity(glow ? 0.7 : 0.12), radius: glow ? 11 : 2)
      .opacity(glow ? 1.0 : 0.7)
      .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: glow)
      .frame(maxWidth: 420)
      .onAppear { glow = true }
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(3))
          withAnimation(.easeInOut(duration: 0.45)) {
            index = (index + 1) % Self.messages.count
          }
        }
      }
  }
}

private struct ModelNotReadyBanner: View {
  var status: ModelStatus
  var openSettings: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: iconName)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Open Settings") {
        openSettings()
      }
      .buttonStyle(.bordered)
      .pointerStyle(.link)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
  }

  private var iconName: String {
    switch status {
    case .downloading, .loading, .waitingForNetwork: return "arrow.down.circle"
    case .failed: return "exclamationmark.triangle.fill"
    default: return "arrow.down.circle"
    }
  }

  private var iconColor: Color {
    switch status {
    case .failed: return .red
    case .downloading, .loading, .waitingForNetwork: return .orange
    default: return .accentColor
    }
  }

  private var title: String {
    switch status {
    case .downloading, .loading, .waitingForNetwork:
      return "Preparing transcription model — \(status.displayLabel)"
    case .failed:
      return "Model download failed"
    default:
      return "Whisper model not downloaded"
    }
  }

  private var subtitle: String {
    switch status {
    case .failed:
      return "Open Settings to retry the download."
    case .downloading, .loading, .waitingForNetwork:
      return "You can record once the model is ready."
    default:
      return "Download the model from Settings before starting a recording."
    }
  }
}
