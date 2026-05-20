import SwiftUI

struct RecorderPanelView: View {
  var recorder: MeetingRecorder

  @AppStorage("recordingLocaleIdentifier") private var localeIdentifier = Locale.defaultRecordingLocaleIdentifier
  @AppStorage("selectedMicrophoneDeviceID") private var selectedMicrophoneDeviceID = ""
  @State private var title = ""
  @State private var microphones: [MicrophoneDevice] = []

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
    }
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
      .disabled(!canRecord)

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
