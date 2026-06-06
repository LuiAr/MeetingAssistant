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
  @State private var transcriptText = ""

  var body: some View {
    ScrollView {
      Text(transcriptText)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle(metadata.title)
    .navigationSubtitle(subtitle)
    .task(id: metadata.id) {
      load()
    }
  }

  private var subtitle: String {
    "\(metadata.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(TimecodeFormatter.string(from: metadata.activeDuration))"
  }

  private func load() {
    if let document = try? store.document(for: metadata) {
      transcriptText = MarkdownExporter.transcript(for: document)
    } else {
      transcriptText = store.transcriptText(for: metadata)
    }
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
