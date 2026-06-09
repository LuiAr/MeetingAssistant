import Foundation
import Observation

/// Process-wide handle to the singleton `RecordingStore` + `MeetingRecorder` so multiple
/// SwiftUI scenes (main library window, dedicated recording window) can observe the same
/// state. Mirrors the singleton pattern already used by `ModelDownloadManager.shared`.
@MainActor
@Observable
public final class AppSession {
  public static let shared = AppSession()

  public let store: RecordingStore
  public let recorder: MeetingRecorder

  public init(rootDirectory: URL = StorageLocationPreferences.recordingsDirectory()) {
    let store = RecordingStore(rootDirectory: rootDirectory)
    self.store = store
    self.recorder = MeetingRecorder(store: store)
  }
}
