import Foundation

/// Resolves and persists the two user-configurable storage locations: where recordings are
/// saved and where the Whisper model is downloaded. Both have sensible defaults under the
/// user's home folder and can be overridden to any directory (for example an external drive).
///
/// The resolution logic is pure and `static` so it can be unit-tested without touching the
/// real `UserDefaults`. The app is not sandboxed, so plain absolute paths are persisted rather
/// than security-scoped bookmarks.
public enum StorageLocationPreferences {
  public static let recordingsDirectoryKey = "recordingsDirectoryPath"
  public static let modelDirectoryKey = "modelDirectoryPath"

  /// Default recordings folder: ~/Documents/MeetingAssistant Recordings.
  public static var defaultRecordingsDirectory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeetingAssistant Recordings", isDirectory: true)
  }

  /// Default model folder: ~/Library/Application Support/MeetingAssistant/WhisperKit.
  public static var defaultModelDirectory: URL {
    let support = (try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    )) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    return support
      .appendingPathComponent("MeetingAssistant", isDirectory: true)
      .appendingPathComponent("WhisperKit", isDirectory: true)
  }

  /// The effective recordings directory, honouring a stored override when present.
  public static func recordingsDirectory(defaults: UserDefaults = .standard) -> URL {
    resolveDirectory(
      storedPath: defaults.string(forKey: recordingsDirectoryKey),
      default: defaultRecordingsDirectory
    )
  }

  /// The effective model directory, honouring a stored override when present.
  public static func modelDirectory(defaults: UserDefaults = .standard) -> URL {
    resolveDirectory(
      storedPath: defaults.string(forKey: modelDirectoryKey),
      default: defaultModelDirectory
    )
  }

  /// Persists a recordings directory override. Passing `nil` (or the default directory)
  /// clears the override so the default is used again.
  public static func setRecordingsDirectory(_ url: URL?, defaults: UserDefaults = .standard) {
    setDirectory(url, forKey: recordingsDirectoryKey, default: defaultRecordingsDirectory, defaults: defaults)
  }

  /// Persists a model directory override. Passing `nil` (or the default directory) clears the
  /// override so the default is used again.
  public static func setModelDirectory(_ url: URL?, defaults: UserDefaults = .standard) {
    setDirectory(url, forKey: modelDirectoryKey, default: defaultModelDirectory, defaults: defaults)
  }

  public static func isUsingCustomRecordingsDirectory(defaults: UserDefaults = .standard) -> Bool {
    recordingsDirectory(defaults: defaults).standardizedFileURL != defaultRecordingsDirectory.standardizedFileURL
  }

  public static func isUsingCustomModelDirectory(defaults: UserDefaults = .standard) -> Bool {
    modelDirectory(defaults: defaults).standardizedFileURL != defaultModelDirectory.standardizedFileURL
  }

  /// Pure resolution: a non-empty stored path wins, otherwise the supplied default is used.
  /// Exposed (non-public) so unit tests can exercise it directly.
  static func resolveDirectory(storedPath: String?, default defaultURL: URL) -> URL {
    guard let storedPath else { return defaultURL }
    let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return defaultURL }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
  }

  /// Pure persistence: storing the default directory (or `nil`) removes the key so the
  /// resolved value falls back to the default.
  static func setDirectory(_ url: URL?, forKey key: String, default defaultURL: URL, defaults: UserDefaults) {
    guard let url, url.standardizedFileURL != defaultURL.standardizedFileURL else {
      defaults.removeObject(forKey: key)
      return
    }
    defaults.set(url.path, forKey: key)
  }
}

/// Tracks whether the first-run onboarding has been completed and where in the flow the user
/// is, so a relaunch (needed to apply a freshly granted Screen Recording permission) resumes
/// the wizard rather than restarting it.
public enum OnboardingPreferences {
  public static let isCompleteKey = "hasCompletedOnboarding"
  public static let stepKey = "onboardingStep"

  public static func isComplete(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: isCompleteKey)
  }

  public static func setComplete(_ complete: Bool, defaults: UserDefaults = .standard) {
    defaults.set(complete, forKey: isCompleteKey)
  }

  public static func step(defaults: UserDefaults = .standard) -> Int {
    defaults.integer(forKey: stepKey)
  }

  public static func setStep(_ step: Int, defaults: UserDefaults = .standard) {
    defaults.set(step, forKey: stepKey)
  }

  /// Resets onboarding so the wizard runs again from the first step. Used by "Re-run setup".
  public static func reset(defaults: UserDefaults = .standard) {
    defaults.set(false, forKey: isCompleteKey)
    defaults.set(0, forKey: stepKey)
  }
}
