import AppKit
import SwiftUI

struct RecordingDetailView: View {
  var metadata: RecordingMetadata
  var store: RecordingStore

  @State private var markdown = ""
  @State private var document: RecordingDocument?
  @State private var searchText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding()

      Divider()

      ScrollView {
        Text(filteredMarkdown)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .searchable(text: $searchText)
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

        Text("\(metadata.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(TimecodeFormatter.string(from: metadata.activeDuration)) · \(metadata.localeIdentifier)")
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
      } label: {
        Label("Copy Markdown", systemImage: "doc.on.doc")
      }

      Button {
        if let document {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(MarkdownExporter.aiContext(for: document), forType: .string)
        }
      } label: {
        Label("Copy AI Context", systemImage: "sparkles")
      }
      .disabled(document == nil)

      Button {
        store.revealInFinder(metadata)
      } label: {
        Label("Reveal", systemImage: "folder")
      }

      ShareLink(item: store.transcriptURL(for: metadata)) {
        Label("Share", systemImage: "square.and.arrow.up")
      }
    }
  }

  private var filteredMarkdown: String {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return markdown }
    return markdown
      .components(separatedBy: .newlines)
      .filter { $0.localizedCaseInsensitiveContains(query) }
      .joined(separator: "\n")
  }

  private func load() {
    markdown = store.transcriptText(for: metadata)
    document = try? store.document(for: metadata)
  }
}

