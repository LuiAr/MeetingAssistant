import AppKit
import SwiftUI

private enum AIContextKey {
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

  @State private var document: RecordingDocument?
  @State private var transcriptText = ""
  @State private var searchText = ""
  @State private var showInfo = false

  @AppStorage(AIContextKey.date) private var includeDate = true
  @AppStorage(AIContextKey.duration) private var includeDuration = true
  @AppStorage(AIContextKey.locale) private var includeLocale = false
  @AppStorage(AIContextKey.status) private var includeStatus = false
  @AppStorage(AIContextKey.files) private var includeFiles = false
  @AppStorage(AIContextKey.pauses) private var includePauses = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding()

      Divider()

      ScrollView {
        Text(filteredTranscript)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .searchable(text: $searchText)
    }
    .inspector(isPresented: $showInfo) {
      RecordingInfoPanel(metadata: metadata, document: document)
        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
    }
    .task(id: metadata.id) {
      load()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(metadata.title)
          .font(.title2.weight(.semibold))
          .lineLimit(2)

        Text("\(metadata.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(TimecodeFormatter.string(from: metadata.activeDuration))")
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        copyAIContext()
      } label: {
        Label("Copy AI Context", systemImage: "sparkles")
      }
      .disabled(document == nil)

      Menu {
        Button {
          store.revealInFinder(metadata)
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
      .menuStyle(.button)
      .fixedSize()

      Button {
        showInfo.toggle()
      } label: {
        Label("Info", systemImage: "info.circle")
      }
      .help("Show recording details")
    }
  }

  private var filteredTranscript: String {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return transcriptText }
    return transcriptText
      .components(separatedBy: .newlines)
      .filter { $0.localizedCaseInsensitiveContains(query) }
      .joined(separator: "\n")
  }

  private var aiContextOptions: MarkdownExporter.AIContextOptions {
    MarkdownExporter.AIContextOptions(
      includeDate: includeDate,
      includeDuration: includeDuration,
      includeLocale: includeLocale,
      includeStatus: includeStatus,
      includeFiles: includeFiles,
      includePauses: includePauses
    )
  }

  private func copyAIContext() {
    guard let document else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      MarkdownExporter.aiContext(for: document, options: aiContextOptions),
      forType: .string
    )
  }

  private func copyTranscriptOnly() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcriptText, forType: .string)
  }

  private func load() {
    let document = try? store.document(for: metadata)
    self.document = document
    transcriptText = document.map(MarkdownExporter.transcript(for:))
      ?? store.transcriptText(for: metadata)
  }
}

private struct RecordingInfoPanel: View {
  var metadata: RecordingMetadata
  var document: RecordingDocument?

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
  }
}
