import AppKit
import SwiftUI

enum AIContextKey {
  static let date = "aiContextIncludeDate"
  static let duration = "aiContextIncludeDuration"
  static let locale = "aiContextIncludeLocale"
  static let status = "aiContextIncludeStatus"
  static let files = "aiContextIncludeFiles"
  static let pauses = "aiContextIncludePauses"
}

struct RecordingDetailView: View {
  var metadata: RecordingMetadata
  var store: RecordingStore

  /// Structured transcript rows, preferred when a document is available.
  @State private var segments: [TranscriptSegment] = []
  /// Plain-text transcript, used only when there are no structured segments.
  @State private var plainFallback: String?

  var body: some View {
    transcriptCard
      .padding(20)
      .navigationTitle(metadata.title)
      .navigationSubtitle(subtitle)
      .task(id: metadata.id) {
        load()
      }
  }

  private var transcriptCard: some View {
    ScrollView {
      if segments.isEmpty {
        Text(plainFallback ?? "No transcript text was produced.")
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(plainFallback == nil ? .secondary : .primary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(18)
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
            transcriptRow(index: index, segment: segment)
            if index < segments.count - 1 {
              Divider().opacity(0.35)
            }
          }
        }
        .textSelection(.enabled)
        .padding(.vertical, 6)
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
  }

  private func transcriptRow(index: Int, segment: TranscriptSegment) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .trailing, spacing: 1) {
        Text("\(index + 1)")
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.tertiary)
        Text(TimecodeFormatter.string(from: segment.startTime))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      .frame(width: 62, alignment: .trailing)

      VStack(alignment: .leading, spacing: 2) {
        Text(segment.speaker.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(speakerColor(segment.speaker))
        Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 5)
  }

  private func speakerColor(_ speaker: SpeakerLabel) -> Color {
    switch speaker {
    case .you: return .accentColor
    case .computerAudio: return .purple
    case .mixed: return .secondary
    }
  }

  private var subtitle: String {
    "\(metadata.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(TimecodeFormatter.string(from: metadata.activeDuration))"
  }

  private func load() {
    guard let document = try? store.document(for: metadata) else {
      segments = []
      plainFallback = normalizedFallback()
      return
    }
    let rows = PauseCompactor.compact(document.transcript, pauses: document.pauses)
      .sorted { $0.startTime < $1.startTime }
      .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    segments = rows
    plainFallback = rows.isEmpty ? normalizedFallback() : nil
  }

  /// The plain transcript text, or nil when it is empty so the view shows a clear
  /// "no transcript" message instead of a blank card.
  private func normalizedFallback() -> String? {
    let text = store.transcriptText(for: metadata)
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }
}

struct RecordingInfoPanel: View {
  var metadata: RecordingMetadata
  var store: RecordingStore

  @State private var document: RecordingDocument?

  @AppStorage(AIContextKey.date) private var includeDate = true
  @AppStorage(AIContextKey.duration) private var includeDuration = true
  @AppStorage(AIContextKey.locale) private var includeLocale = false
  @AppStorage(AIContextKey.status) private var includeStatus = false
  @AppStorage(AIContextKey.files) private var includeFiles = false
  @AppStorage(AIContextKey.pauses) private var includePauses = false

  var body: some View {
    Form {
      Section("Details") {
        LabeledContent("Title", value: metadata.title)
        LabeledContent("Created", value: metadata.createdAt.formatted(date: .abbreviated, time: .standard))
        LabeledContent("Started", value: metadata.startedAt.formatted(date: .abbreviated, time: .standard))
        if let endedAt = metadata.endedAt {
          LabeledContent("Ended", value: endedAt.formatted(date: .abbreviated, time: .standard))
        }
        LabeledContent("Duration", value: TimecodeFormatter.string(from: metadata.duration))
        LabeledContent("Active recording time", value: TimecodeFormatter.string(from: metadata.activeDuration))
        LabeledContent("Locale", value: metadata.localeIdentifier)
        LabeledContent("Status", value: metadata.status.displayName)
      }

      Section("Files") {
        LabeledContent("Transcript", value: metadata.transcriptFileName)
        if let systemAudioFileName = metadata.systemAudioFileName {
          LabeledContent("Computer audio", value: systemAudioFileName)
        }
        if let microphoneAudioFileName = metadata.microphoneAudioFileName {
          LabeledContent("Microphone", value: microphoneAudioFileName)
        }
        if let mixedAudioFileName = metadata.mixedAudioFileName {
          LabeledContent("Mixed audio", value: mixedAudioFileName)
        }
      }

      Section("Pauses") {
        if let pauses = document?.pauses, !pauses.isEmpty {
          ForEach(Array(pauses.enumerated()), id: \.offset) { _, pause in
            Text("\(TimecodeFormatter.string(from: pause.startOffset))–\(TimecodeFormatter.string(from: pause.endOffset)) (\(TimecodeFormatter.string(from: pause.duration)))")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        } else {
          Text("None")
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Toggle("Date & times", isOn: $includeDate)
        Toggle("Duration", isOn: $includeDuration)
        Toggle("Locale", isOn: $includeLocale)
        Toggle("Status", isOn: $includeStatus)
        Toggle("File names", isOn: $includeFiles)
        Toggle("Pauses", isOn: $includePauses)
      } header: {
        Text("Include in AI Context")
      } footer: {
        Text("Title and the transcript are always included.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .task(id: metadata.id) {
      document = try? store.document(for: metadata)
    }
  }
}
