import Foundation

public enum MarkdownExporter {
  public static func markdown(for document: RecordingDocument) -> String {
    var lines: [String] = []
    let metadata = document.metadata
    let compactedTranscript = PauseCompactor.compact(document.transcript, pauses: document.pauses)

    lines.append("---")
    lines.append("id: \(metadata.id.uuidString)")
    lines.append("title: \(yamlEscaped(metadata.title))")
    lines.append("created_at: \(metadata.createdAt.ISO8601Format())")
    lines.append("started_at: \(metadata.startedAt.ISO8601Format())")
    if let endedAt = metadata.endedAt {
      lines.append("ended_at: \(endedAt.ISO8601Format())")
    }
    lines.append("duration: \(Int(metadata.duration.rounded()))")
    lines.append("active_duration: \(Int(metadata.activeDuration.rounded()))")
    lines.append("locale: \(metadata.localeIdentifier)")
    lines.append("status: \(metadata.status.rawValue)")
    lines.append("---")
    lines.append("")
    lines.append("# \(metadata.title)")
    lines.append("")
    lines.append("## Metadata")
    lines.append("")
    lines.append("- Created: \(metadata.createdAt.formatted(date: .abbreviated, time: .standard))")
    lines.append("- Started: \(metadata.startedAt.formatted(date: .abbreviated, time: .standard))")
    if let endedAt = metadata.endedAt {
      lines.append("- Ended: \(endedAt.formatted(date: .abbreviated, time: .standard))")
    }
    lines.append("- Duration: \(TimecodeFormatter.string(from: metadata.duration))")
    lines.append("- Active recording time: \(TimecodeFormatter.string(from: metadata.activeDuration))")
    lines.append("- Locale: \(metadata.localeIdentifier)")
    lines.append("")
    lines.append("## Files")
    lines.append("")
    lines.append("- Transcript: `\(metadata.transcriptFileName)`")
    if let systemAudioFileName = metadata.systemAudioFileName {
      lines.append("- Computer audio: `\(systemAudioFileName)`")
    }
    if let microphoneAudioFileName = metadata.microphoneAudioFileName {
      lines.append("- Microphone: `\(microphoneAudioFileName)`")
    }
    if let mixedAudioFileName = metadata.mixedAudioFileName {
      lines.append("- Mixed audio: `\(mixedAudioFileName)`")
    }
    lines.append("")
    lines.append("## Pauses")
    lines.append("")
    if document.pauses.isEmpty {
      lines.append("- None")
    } else {
      for pause in document.pauses {
        let start = TimecodeFormatter.string(from: pause.startOffset)
        let end = TimecodeFormatter.string(from: pause.endOffset)
        lines.append("- \(start)-\(end) (\(TimecodeFormatter.string(from: pause.duration)))")
      }
    }
    lines.append("")
    lines.append("## Transcript")
    lines.append("")

    if compactedTranscript.isEmpty {
      lines.append("_No transcript text was produced._")
    } else {
      for segment in compactedTranscript.sorted(by: { $0.startTime < $1.startTime }) {
        let timecode = TimecodeFormatter.string(from: segment.startTime)
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        lines.append("[\(timecode)] \(segment.speaker.rawValue): \(text)")
        lines.append("")
      }
    }

    return lines.joined(separator: "\n")
  }

  public static func aiContext(for document: RecordingDocument) -> String {
    let metadata = document.metadata
    var lines: [String] = []
    lines.append("Meeting: \(metadata.title)")
    lines.append("Date: \(metadata.startedAt.formatted(date: .abbreviated, time: .shortened))")
    lines.append("Duration: \(TimecodeFormatter.string(from: metadata.activeDuration))")
    lines.append("")
    lines.append("Transcript:")
    lines.append("")
    lines.append(markdown(for: document))
    return lines.joined(separator: "\n")
  }

  private static func yamlEscaped(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
  }
}

