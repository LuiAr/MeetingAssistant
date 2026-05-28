import SwiftUI

struct RecorderPanelView: View {
  var recorder: MeetingRecorder

  @AppStorage("recordingLocaleIdentifier") private var localeIdentifier = Locale.defaultRecordingLocaleIdentifier
  @AppStorage("selectedMicrophoneDeviceID") private var selectedMicrophoneDeviceID = ""
  @State private var title = ""
  @State private var microphones: [MicrophoneDevice] = []
  @State private var modelManager = ModelDownloadManager.shared
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Meeting Recorder")
            .font(.title3.weight(.semibold))

          HStack(spacing: 8) {
            Circle()
              .fill(statusColor)
              .frame(width: 8, height: 8)
            Text(recorder.status.displayName)
              .foregroundStyle(.secondary)
            Text(TimecodeFormatter.string(from: recorder.activeElapsed))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          .font(.callout)
        }

        Spacer()

        controlButtons
      }

      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
        GridRow {
          Text("Title")
            .foregroundStyle(.secondary)
          TextField("Meeting title", text: $title)
            .textFieldStyle(.roundedBorder)
        }

        GridRow {
          Text("Microphone")
            .foregroundStyle(.secondary)
          Picker("Microphone", selection: $selectedMicrophoneDeviceID) {
            Text("System Default").tag("")
            ForEach(microphones) { microphone in
              Text(microphone.name).tag(microphone.id)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 360)
        }

        GridRow {
          Text("Locale")
            .foregroundStyle(.secondary)
          TextField("Locale", text: $localeIdentifier)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
        }
      }

      HStack(spacing: 18) {
        LevelMeterView(title: "Computer", level: recorder.levels.system)
        LevelMeterView(title: "Mic", level: recorder.levels.microphone)
      }

      LiveTranscriptStrip(segments: recorder.liveTranscript)

      if !isModelReady {
        ModelNotReadyBanner(status: modelManager.status) {
          openSettings()
        }
      }

      if let progress = recorder.transcriptionProgress {
        TranscriptionProgressBanner(progress: progress)
      }

      if let errorMessage = recorder.errorMessage {
        Text(errorMessage)
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
    }
    .task {
      microphones = MicrophoneDeviceProvider.devices()
      modelManager.refreshStatus()
    }
  }

  private var isModelReady: Bool {
    modelManager.isModelOnDisk()
  }

  @ViewBuilder
  private var controlButtons: some View {
    HStack(spacing: 8) {
      Button {
        Task {
          await recorder.startRecording(
            title: title,
            localeIdentifier: localeIdentifier,
            microphoneDeviceID: selectedMicrophoneDeviceID.isEmpty ? nil : selectedMicrophoneDeviceID
          )
        }
      } label: {
        Label("Record", systemImage: "record.circle")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canRecord || !isModelReady)
      .help(isModelReady ? "" : "Download the Whisper model in Settings before recording.")

      Button {
        recorder.pause()
      } label: {
        Label("Pause", systemImage: "pause.fill")
      }
      .disabled(recorder.status != .recording)

      Button {
        recorder.resume()
      } label: {
        Label("Resume", systemImage: "play.fill")
      }
      .disabled(recorder.status != .paused)

      Button {
        Task {
          await recorder.stop()
        }
      } label: {
        Label("Stop", systemImage: "stop.fill")
      }
      .disabled(recorder.status != .recording && recorder.status != .paused)
    }
  }

  private var canRecord: Bool {
    switch recorder.status {
    case .idle, .completed, .failed:
      return true
    default:
      return false
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

private struct TranscriptionProgressBanner: View {
  var progress: WhisperTranscriptionProgress

  var body: some View {
    HStack(spacing: 10) {
      ProgressView(value: fractionValue)
        .progressViewStyle(.linear)
        .frame(maxWidth: 220)
      Text(label)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 10)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
  }

  private var fractionValue: Double? {
    switch progress.phase {
    case .downloadingModel(let fraction):
      return fraction
    case .loadingModel:
      return nil
    case .transcribing(let fraction):
      return fraction
    }
  }

  private var label: String {
    switch progress.phase {
    case .downloadingModel(let fraction):
      return "Downloading Whisper model — \(Int(fraction * 100))%"
    case .loadingModel:
      return "Loading Whisper model…"
    case .transcribing(let fraction):
      return "Transcribing — \(Int(fraction * 100))%"
    }
  }
}

private struct LiveTranscriptStrip: View {
  var segments: [TranscriptSegment]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Live Transcript")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      if segments.isEmpty {
        Text("Transcript is generated from the saved audio after you stop recording.")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        ForEach(segments.suffix(3)) { segment in
          Text("[\(TimecodeFormatter.string(from: segment.startTime))] \(segment.speaker.rawValue): \(segment.text)")
            .lineLimit(1)
            .textSelection(.enabled)
        }
      }
    }
    .font(.callout)
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
