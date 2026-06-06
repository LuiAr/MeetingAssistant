import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LibrarySortOrder: String, CaseIterable, Identifiable {
  case newest
  case oldest
  case title
  case longest

  var id: String { rawValue }

  var label: String {
    switch self {
    case .newest: return "Newest First"
    case .oldest: return "Oldest First"
    case .title: return "Title"
    case .longest: return "Longest"
    }
  }

  var systemImage: String {
    switch self {
    case .newest: return "arrow.down"
    case .oldest: return "arrow.up"
    case .title: return "textformat"
    case .longest: return "clock"
    }
  }

  /// Newest/Oldest keep the date-bucket sections; Title/Longest show a flat list.
  var groupsByDate: Bool {
    self == .newest || self == .oldest
  }
}

struct SidebarView: View {
  var recordings: [RecordingMetadata]
  @Binding var selection: UUID?
  @Binding var searchText: String
  var store: RecordingStore

  @AppStorage("librarySortOrder") private var sortOrderRaw = LibrarySortOrder.newest.rawValue

  @State private var renameTarget: RecordingMetadata?
  @State private var renameText = ""
  @State private var deleteTarget: RecordingMetadata?

  private var sortOrder: LibrarySortOrder {
    LibrarySortOrder(rawValue: sortOrderRaw) ?? .newest
  }

  var body: some View {
    VStack(spacing: 0) {
      header

      List(selection: $selection) {
        ForEach(sections) { section in
          Section {
            ForEach(section.items) { recording in
              row(for: recording)
                .tag(recording.id)
                .contextMenu { contextMenu(for: recording) }
            }
          } header: {
            if let title = section.title {
              Text(title)
            }
          }
        }
      }
      .listStyle(.sidebar)
      .overlay {
        if recordings.isEmpty {
          emptyState
        }
      }
    }
    // NavigationSplitView applies the inset sidebar's top safe area inconsistently — it's
    // present when the detail shows a transcript but absent on the landing view, so a fixed
    // offset would be right in one state and wrong in the other. Ignore the top safe area
    // and pin the header a fixed distance from the window's physical top so it clears the
    // traffic-light controls identically in every state.
    .ignoresSafeArea(.container, edges: .top)
    .alert("Rename Recording", isPresented: renamePresented) {
      TextField("Name", text: $renameText)
      Button("Cancel", role: .cancel) {}
      Button("Rename") { commitRename() }
    } message: {
      Text("Enter a new name for this recording.")
    }
    .confirmationDialog(
      "Delete Recording?",
      isPresented: deletePresented,
      presenting: deleteTarget
    ) { recording in
      Button("Delete", role: .destructive) {
        if selection == recording.id { selection = nil }
        try? store.delete(recording)
      }
      Button("Cancel", role: .cancel) {}
    } message: { recording in
      Text("“\(recording.title)” and its audio and transcript files will be permanently deleted. This cannot be undone.")
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text("Library")
          .font(.title2.weight(.bold))
        Spacer()
        sortMenu
      }

      searchField
    }
    .padding(.horizontal, 12)
    // The inset sidebar draws content from the very top of the window (its top safe-area
    // inset is ~0), so this reserves the title-bar height for the traffic-light controls.
    .padding(.top, 40)
    .padding(.bottom, 8)
    .background(.ultraThinMaterial)
  }

  private var sortMenu: some View {
    Menu {
      Picker("Sort By", selection: $sortOrderRaw) {
        ForEach(LibrarySortOrder.allCases) { order in
          Label(order.label, systemImage: order.systemImage)
            .tag(order.rawValue)
        }
      }
      .pickerStyle(.inline)
    } label: {
      Image(systemName: "arrow.up.arrow.down")
        .foregroundStyle(.secondary)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Sort recordings")
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search", text: $searchText)
        .textFieldStyle(.plain)

      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear search")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Rows

  private func row(for recording: RecordingMetadata) -> some View {
    HStack(spacing: 10) {
      Image(systemName: iconName(for: recording.status))
        .foregroundStyle(iconColor(for: recording.status))
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(recording.title)
          .lineLimit(1)

        Text(detailText(for: recording))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private func contextMenu(for recording: RecordingMetadata) -> some View {
    Button {
      beginRename(recording)
    } label: {
      Label("Rename", systemImage: "pencil")
    }

    Button {
      store.revealInFinder(recording)
    } label: {
      Label("Reveal in Finder", systemImage: "folder")
    }

    Button {
      exportMarkdown(recording)
    } label: {
      Label("Export Markdown…", systemImage: "square.and.arrow.up")
    }

    Divider()

    Button(role: .destructive) {
      deleteTarget = recording
    } label: {
      Label("Delete", systemImage: "trash")
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label(
        searchText.isEmpty ? "No Recordings" : "No Results",
        systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass"
      )
    } description: {
      Text(
        searchText.isEmpty
          ? "Start a meeting and it will appear here."
          : "No recordings match “\(searchText)”."
      )
    }
  }

  // MARK: - Rename / Delete plumbing

  private var renamePresented: Binding<Bool> {
    Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
  }

  private var deletePresented: Binding<Bool> {
    Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
  }

  private func beginRename(_ recording: RecordingMetadata) {
    renameText = recording.title
    renameTarget = recording
  }

  private func commitRename() {
    guard let recording = renameTarget else { return }
    try? store.rename(recording, to: renameText)
    renameTarget = nil
  }

  private func exportMarkdown(_ recording: RecordingMetadata) {
    guard let document = try? store.document(for: recording) else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(recording.title).md"
    if let markdownType = UTType(filenameExtension: "md") {
      panel.allowedContentTypes = [markdownType]
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? MarkdownExporter.markdown(for: document).write(to: url, atomically: true, encoding: .utf8)
  }

  // MARK: - Sorting & grouping

  private var sections: [LibrarySection] {
    let sorted = sortedRecordings()
    guard sortOrder.groupsByDate else {
      return [LibrarySection(id: "all", title: nil, items: sorted)]
    }
    return groupByDate(sorted, ascending: sortOrder == .oldest)
  }

  private func sortedRecordings() -> [RecordingMetadata] {
    switch sortOrder {
    case .newest:
      return recordings.sorted { $0.startedAt > $1.startedAt }
    case .oldest:
      return recordings.sorted { $0.startedAt < $1.startedAt }
    case .title:
      return recordings.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    case .longest:
      return recordings.sorted { $0.activeDuration > $1.activeDuration }
    }
  }

  private func groupByDate(_ items: [RecordingMetadata], ascending: Bool) -> [LibrarySection] {
    let calendar = Calendar.current
    let now = Date()
    let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now

    func bucket(for date: Date) -> (order: Int, title: String) {
      if calendar.isDateInToday(date) { return (0, "Today") }
      if calendar.isDateInYesterday(date) { return (1, "Yesterday") }
      if date >= weekAgo { return (2, "Previous 7 Days") }
      return (3, "Earlier")
    }

    var groups: [Int: (title: String, items: [RecordingMetadata])] = [:]
    for item in items {
      let result = bucket(for: item.startedAt)
      groups[result.order, default: (result.title, [])].items.append(item)
    }

    let orderedKeys = ascending ? groups.keys.sorted(by: >) : groups.keys.sorted()
    return orderedKeys.compactMap { key in
      guard let group = groups[key] else { return nil }
      return LibrarySection(id: group.title, title: group.title, items: group.items)
    }
  }

  // MARK: - Formatting

  private func detailText(for recording: RecordingMetadata) -> String {
    "\(recording.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(TimecodeFormatter.string(from: recording.activeDuration))"
  }

  private func iconName(for status: RecordingStatus) -> String {
    switch status {
    case .recording:
      return "record.circle"
    case .paused:
      return "pause.circle"
    case .failed:
      return "exclamationmark.triangle"
    default:
      return "doc.text"
    }
  }

  private func iconColor(for status: RecordingStatus) -> Color {
    switch status {
    case .recording:
      return .red
    case .paused:
      return .orange
    case .failed:
      return .yellow
    default:
      return .secondary
    }
  }
}

private struct LibrarySection: Identifiable {
  let id: String
  let title: String?
  let items: [RecordingMetadata]
}
