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

  @State private var searchText = ""
  @State private var currentMatchIndex = 0

  /// The maximum width of the reading column, so long transcripts stay comfortable to read on
  /// a wide window rather than running edge to edge.
  private let readingWidth: CGFloat = 720

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)

      Divider()

      transcriptArea
        .padding(20)
    }
    .navigationTitle(metadata.title)
    .task(id: metadata.id) {
      load()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 10) {
        Text(metadata.title)
          .font(.title2.weight(.semibold))
          .lineLimit(1)

        HStack(spacing: 8) {
          chip("calendar", dateString)
          chip("clock", TimecodeFormatter.string(from: metadata.activeDuration))
          if !segments.isEmpty {
            chip("person.2", pluralised(speakerCount, "speaker"))
            chip("textformat", pluralised(wordCount, "word"))
          }
        }
      }

      Spacer(minLength: 0)

      searchBar
        .frame(width: 260)
    }
  }

  private func chip(_ systemImage: String, _ text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
      Text(text)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(.quaternary, in: Capsule())
  }

  private var searchBar: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search transcript", text: $searchText)
        .textFieldStyle(.plain)

      if !trimmedQuery.isEmpty {
        if matches.isEmpty {
          Text("None")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("\(min(currentMatchIndex, matches.count - 1) + 1) of \(matches.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

          Button {
            goToPreviousMatch()
          } label: {
            Image(systemName: "chevron.up")
          }
          .buttonStyle(.plain)
          .disabled(matches.count < 2)

          Button {
            goToNextMatch()
          } label: {
            Image(systemName: "chevron.down")
          }
          .buttonStyle(.plain)
          .disabled(matches.count < 2)
        }
      }

      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Transcript

  private var transcriptArea: some View {
    ScrollViewReader { proxy in
      ScrollView {
        content
          .frame(maxWidth: readingWidth)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 28)
          .padding(.vertical, 24)
      }
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
      .onChange(of: currentMatchIndex) { _, _ in
        scrollToCurrentMatch(proxy)
      }
      .onChange(of: searchText) { _, _ in
        currentMatchIndex = 0
        scrollToCurrentMatch(proxy)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if segments.isEmpty {
      Text(plainFallback ?? "No transcript text was produced.")
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(plainFallback == nil ? .secondary : .primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(blocks) { block in
          blockView(block)
        }
      }
      .textSelection(.enabled)
    }
  }

  private func blockView(_ block: SpeakerBlock) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Circle()
          .fill(speakerColor(block.speaker))
          .frame(width: 7, height: 7)
        Text(block.speaker.rawValue)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(speakerColor(block.speaker))
        Spacer(minLength: 8)
        Text(TimecodeFormatter.string(from: block.startTime))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.tertiary)
      }

      ForEach(block.lines) { line in
        Text(attributedText(for: line))
          .font(.system(size: 15))
          .lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .id(line.id)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(speakerColor(block.speaker).opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  /// Builds the line text with case-insensitive search matches highlighted. The match the user
  /// is currently on is highlighted more strongly than the rest.
  private func attributedText(for segment: TranscriptSegment) -> AttributedString {
    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    var attributed = AttributedString(text)
    let query = trimmedQuery
    guard !query.isEmpty else { return attributed }

    var searchStart = text.startIndex
    while let range = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
      let offset = text.distance(from: text.startIndex, to: range.lowerBound)
      if let low = AttributedString.Index(range.lowerBound, within: attributed),
         let high = AttributedString.Index(range.upperBound, within: attributed) {
        let isCurrent = currentMatch?.segmentID == segment.id && currentMatch?.offset == offset
        attributed[low..<high].backgroundColor = isCurrent ? Color.orange.opacity(0.7) : Color.yellow.opacity(0.45)
        attributed[low..<high].foregroundColor = .black
      }
      if range.lowerBound == range.upperBound { break }
      searchStart = range.upperBound
    }
    return attributed
  }

  // MARK: - Search matches

  private struct MatchLocation: Equatable {
    let segmentID: UUID
    let offset: Int
  }

  private var trimmedQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var matches: [MatchLocation] {
    let query = trimmedQuery
    guard !query.isEmpty else { return [] }

    var result: [MatchLocation] = []
    for segment in segments {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      var searchStart = text.startIndex
      while let range = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
        result.append(MatchLocation(segmentID: segment.id, offset: text.distance(from: text.startIndex, to: range.lowerBound)))
        if range.lowerBound == range.upperBound { break }
        searchStart = range.upperBound
      }
    }
    return result
  }

  private var currentMatch: MatchLocation? {
    let all = matches
    guard !all.isEmpty else { return nil }
    return all[min(max(currentMatchIndex, 0), all.count - 1)]
  }

  private func goToNextMatch() {
    guard !matches.isEmpty else { return }
    currentMatchIndex = (currentMatchIndex + 1) % matches.count
  }

  private func goToPreviousMatch() {
    let count = matches.count
    guard count > 0 else { return }
    currentMatchIndex = (currentMatchIndex - 1 + count) % count
  }

  private func scrollToCurrentMatch(_ proxy: ScrollViewProxy) {
    guard let match = currentMatch else { return }
    withAnimation(.easeInOut(duration: 0.25)) {
      proxy.scrollTo(match.segmentID, anchor: .center)
    }
  }

  // MARK: - Grouping

  private struct SpeakerBlock: Identifiable {
    let id: Int
    let speaker: SpeakerLabel
    let lines: [TranscriptSegment]

    var startTime: TimeInterval {
      lines.first?.startTime ?? 0
    }
  }

  /// Groups consecutive segments from the same speaker into a single block, so the transcript
  /// reads like a conversation rather than a flat numbered list.
  private var blocks: [SpeakerBlock] {
    var result: [SpeakerBlock] = []
    for segment in segments {
      if let last = result.last, last.speaker == segment.speaker {
        result[result.count - 1] = SpeakerBlock(id: last.id, speaker: last.speaker, lines: last.lines + [segment])
      } else {
        result.append(SpeakerBlock(id: result.count, speaker: segment.speaker, lines: [segment]))
      }
    }
    return result
  }

  // MARK: - Stats

  private var dateString: String {
    metadata.startedAt.formatted(date: .abbreviated, time: .shortened)
  }

  private var speakerCount: Int {
    Set(segments.map(\.speaker)).count
  }

  private var wordCount: Int {
    segments.reduce(0) { total, segment in
      total + segment.text.split { $0.isWhitespace || $0.isNewline }.count
    }
  }

  private func pluralised(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }

  private func speakerColor(_ speaker: SpeakerLabel) -> Color {
    switch speaker {
    case .you: return .accentColor
    case .computerAudio: return .purple
    case .mixed: return .secondary
    }
  }

  // MARK: - Loading

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
    currentMatchIndex = 0
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
