import SwiftUI

struct RecentMeetingsStackView: View {
  var recordings: [RecordingMetadata]
  var onSelect: (UUID) -> Void
  var onOpenLibrary: () -> Void

  @State private var hoveredRecordingID: UUID?
  @State private var isLibraryButtonHovered = false

  private var recentRecordings: [RecordingMetadata] {
    Array(recordings.prefix(3))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("Recent meetings")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Button(action: onOpenLibrary) {
          HStack(spacing: 4) {
            Text("Open in Library")
            Image(systemName: "arrow.up.right")
              .font(.caption2.weight(.semibold))
          }
          .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Open the most recent meeting in Library")
      }
      .padding(.horizontal, 4)

      VStack(spacing: 9) {
        ForEach(Array(recentRecordings.enumerated()), id: \.element.id) { index, recording in
          recentMeetingCard(recording, index: index)
        }
      }

      Button(action: onOpenLibrary) {
        HStack(spacing: 10) {
          Image(systemName: "books.vertical.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)

          Text("Open Library")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)

          Spacer()

          Image(systemName: "arrow.right")
            .font(.callout.weight(.semibold))
            .foregroundStyle(isLibraryButtonHovered ? .secondary : .tertiary)
            .offset(x: isLibraryButtonHovered ? 2 : 0)
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(.tint.opacity(isLibraryButtonHovered ? 0.10 : 0.065), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.tint.opacity(isLibraryButtonHovered ? 0.24 : 0.14))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .scaleEffect(isLibraryButtonHovered ? 1.01 : 1)
      .shadow(
        color: .black.opacity(isLibraryButtonHovered ? 0.09 : 0.025),
        radius: isLibraryButtonHovered ? 9 : 4,
        y: isLibraryButtonHovered ? 4 : 2
      )
      .onHover { hovering in
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
          isLibraryButtonHovered = hovering
        }
      }
      .help("Open the most recent meeting in Library")
    }
    .frame(maxWidth: 420)
  }

  private func recentMeetingCard(_ recording: RecordingMetadata, index: Int) -> some View {
    let isHovered = hoveredRecordingID == recording.id

    return Button {
      onSelect(recording.id)
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "message.badge.waveform")
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: 40, height: 40)
          .background(.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))

        VStack(alignment: .leading, spacing: 4) {
          Text(index == 0 ? "Most recent" : "Recent meeting")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text(recording.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.callout.weight(.semibold))
          .foregroundStyle(isHovered ? .secondary : .tertiary)
          .offset(x: isHovered ? 2 : 0)
      }
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
      .background(Color.primary.opacity(isHovered ? 0.045 : 0.025), in: RoundedRectangle(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .strokeBorder(.primary.opacity(isHovered ? 0.13 : 0.06))
      }
      .shadow(
        color: .black.opacity(isHovered ? 0.11 : 0.035),
        radius: isHovered ? 12 : 5,
        y: isHovered ? 5 : 2
      )
      .contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .opacity(isHovered ? 1 : baseOpacity(for: index))
    .scaleEffect(isHovered ? 1.012 : 1)
    .offset(y: isHovered ? -2 : 0)
    .onHover { hovering in
      withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
        hoveredRecordingID = hovering ? recording.id : nil
      }
    }
    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hoveredRecordingID)
    .help("Open \(recording.title) in Library")
  }

  private func baseOpacity(for index: Int) -> Double {
    switch index {
    case 1:
      return 0.90
    case 2:
      return 0.82
    default:
      return 1
    }
  }

}
