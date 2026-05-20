import SwiftUI

struct SidebarView: View {
  var recordings: [RecordingMetadata]
  @Binding var selection: UUID?

  var body: some View {
    List(selection: $selection) {
      Section("Recordings") {
        ForEach(recordings) { recording in
          HStack(spacing: 10) {
            Image(systemName: iconName(for: recording.status))
              .foregroundStyle(.secondary)
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
          .tag(recording.id)
        }
      }
    }
    .listStyle(.sidebar)
  }

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
}

