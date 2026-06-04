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

  /// The transcript on its own — the timecoded speaker lines, with no frontmatter,
  /// metadata, files, or pauses. Used for the in-app transcript view and "Copy only
  /// transcript".
  public static func transcript(for document: RecordingDocument) -> String {
    let compactedTranscript = PauseCompactor.compact(document.transcript, pauses: document.pauses)
      .sorted { $0.startTime < $1.startTime }

    let entries: [String] = compactedTranscript.compactMap { segment in
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      let timecode = TimecodeFormatter.string(from: segment.startTime)
      return "[\(timecode)] \(segment.speaker.rawValue): \(text)"
    }

    guard !entries.isEmpty else {
      return "No transcript text was produced."
    }
    return entries.joined(separator: "\n\n")
  }

  /// Which pieces of metadata are prepended to the transcript when building the AI context.
  /// The title and the transcript itself are always included.
  public struct AIContextOptions: Sendable, Equatable {
    public var includeDate: Bool
    public var includeDuration: Bool
    public var includeLocale: Bool
    public var includeStatus: Bool
    public var includeFiles: Bool
    public var includePauses: Bool

    public init(
      includeDate: Bool = true,
      includeDuration: Bool = true,
      includeLocale: Bool = false,
      includeStatus: Bool = false,
      includeFiles: Bool = false,
      includePauses: Bool = false
    ) {
      self.includeDate = includeDate
      self.includeDuration = includeDuration
      self.includeLocale = includeLocale
      self.includeStatus = includeStatus
      self.includeFiles = includeFiles
      self.includePauses = includePauses
    }
  }

  public static func aiContext(
    for document: RecordingDocument,
    options: AIContextOptions = AIContextOptions()
  ) -> String {
    let metadata = document.metadata
    var lines: [String] = []
    lines.append("Meeting: \(metadata.title)")

    if options.includeDate {
      lines.append("Date: \(metadata.startedAt.formatted(date: .abbreviated, time: .shortened))")
      if let endedAt = metadata.endedAt {
        lines.append("Ended: \(endedAt.formatted(date: .abbreviated, time: .shortened))")
      }
    }
    if options.includeDuration {
      lines.append("Duration: \(TimecodeFormatter.string(from: metadata.activeDuration))")
    }
    if options.includeLocale {
      lines.append("Locale: \(metadata.localeIdentifier)")
    }
    if options.includeStatus {
      lines.append("Status: \(metadata.status.rawValue)")
    }
    if options.includeFiles {
      var files: [String] = ["transcript: \(metadata.transcriptFileName)"]
      if let systemAudioFileName = metadata.systemAudioFileName {
        files.append("computer audio: \(systemAudioFileName)")
      }
      if let microphoneAudioFileName = metadata.microphoneAudioFileName {
        files.append("microphone: \(microphoneAudioFileName)")
      }
      if let mixedAudioFileName = metadata.mixedAudioFileName {
        files.append("mixed audio: \(mixedAudioFileName)")
      }
      lines.append("Files: \(files.joined(separator: ", "))")
    }
    if options.includePauses {
      if document.pauses.isEmpty {
        lines.append("Pauses: none")
      } else {
        let pauses = document.pauses.map { pause in
          "\(TimecodeFormatter.string(from: pause.startOffset))-\(TimecodeFormatter.string(from: pause.endOffset))"
        }
        lines.append("Pauses: \(pauses.joined(separator: ", "))")
      }
    }

    lines.append("")
    lines.append("Transcript:")
    lines.append("")
    lines.append(transcript(for: document))
    return lines.joined(separator: "\n")
  }

  private static func yamlEscaped(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
  }
}

