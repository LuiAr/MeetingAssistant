import SwiftUI

/// Hosts the recording controls in their own window. Opened from the landing view with a
/// `NewRecordingSession` value; auto-starts the recording on first appear. Closing the
/// window after Stop is the user's responsibility — focus returns to the library window
/// automatically.
public struct RecordingWindowView: View {
  public let session: NewRecordingSession

  @State private var recorder = AppSession.shared.recorder
  @State private var didAutoStart = false

  public init(session: NewRecordingSession) {
    self.session = session
  }

  public var body: some View {
    RecorderPanelView(recorder: recorder)
      .padding()
      .frame(minWidth: 560, minHeight: 420)
      .navigationTitle(displayTitle)
      .task {
        // Auto-start exactly once per window instance. The recorder itself also guards
        // against double-start, but this prevents a window restoration from re-firing
        // the request on a session whose recording already completed.
        guard !didAutoStart else { return }
        didAutoStart = true
        guard recorder.status == .idle
                || recorder.status == .completed
                || recorder.status == .failed
        else { return }
        await recorder.startRecording(
          title: session.title,
          localeIdentifier: session.localeIdentifier,
          microphoneDeviceID: session.microphoneDeviceID
        )
      }
  }

  private var displayTitle: String {
    let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Recording" : trimmed
  }
}
